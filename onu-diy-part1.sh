#!/bin/bash
# ============================================================
# ONU 编译线 DIY 前置脚本（feeds update 之前执行）
#
# 源码: naoki66/ImmortalWrt-for-Gemtek-brightspeed（不是 pbs05/ponwrt）
# 设备: Nokia XG-040G-MD (UBI)
# 目的: 拿到 naoki66 那套 ONU 用户态栈（顶级 ONU 菜单 luci-app-onu）
#
# ⚠️ 本线与 ponwrt-diy-part1.sh 是两条独立的线, 互不干扰:
#     那条线 = pbs05/ponwrt 源码 + luci-app-pon + luci-app-iptv;
#     这条线 = naoki66 fork 源码 + luci-app-onu。
#     两条线共用 patches/firewall4/ 那一个文件, 但都是只读引用, 不覆写。
#
# 为什么换源码而不是只换 feed —— 三点实测依据:
#   1) 该 fork 的 feeds.conf.default 里 pon_userspace 天然指向
#      naoki66/openwrt-pon-userspace；已核实它与用户给的
#      naoki66/OpenWrt_ONU_CONFIG **内容 diff 为空、HEAD 同为 77a2c09a**
#      (同一个项目的两个仓库名)。luci-app-onu 是它的原生包, 不用我们换源。
#   2) 它自带 scripts/apply-feed-patches.sh + include/feed-patches.mk,
#      把 feed 补丁 hook 进每次 make —— 上游那套机制照用。
#   3) 2010.config 种子里 PON 全家桶已经是 =y, 不用我们从零挑包。
# ============================================================

set -e

# ---------------------------------------------------------------
# 0. 源码树健全性检查 —— 换线最容易犯的错就是脚本跑错源码树
# ---------------------------------------------------------------
for d in scripts target/linux/airoha; do
  if [ ! -d "$d" ]; then
    echo "FATAL: 当前目录 ($PWD) 下没有 $d, 源码树不对"
    exit 1
  fi
done
if [ ! -f 2010.config ]; then
  echo "FATAL: 找不到 2010.config (本线用它做种子配置)"
  echo "       当前目录里的 .config 种子: $(ls -1 *.config 2>/dev/null | tr '\n' ' ')"
  exit 1
fi
echo "=== 源码树检查通过: 种子 2010.config 存在 ==="

# ---------------------------------------------------------------
# 1. 清掉 dl 缓存里被还原出来的 go-mod-cache
#    (从 ponwrt-diy-part1.sh 照搬 —— 同一个坑: 缓存由 restore-key 兜底还原,
#     提取出来的 module 目录残缺, 而构建期 Go 是离线跑的 (GOPROXY=off),
#     缺东西不会补, 直接判失败, 重试多少次都必然复现。)
# ---------------------------------------------------------------
for d in "$PWD/dl/go-mod-cache" /workdir/openwrt/dl/go-mod-cache; do
  if [ -d "$d" ]; then
    echo "删除还原出来的 go-mod-cache: $d (不可信)"
    rm -rf "$d"
  fi
done

# ---------------------------------------------------------------
# 2. 设备必须是 XG-040G-MD (UBI) —— 改 .config 在 diy-part2, 这里先验存在
#
#    为什么用 2010.config 而不是 1710.config:
#      1710.config (XR1710G) 里**没有 PON 包**。溯源 naoki66 自己那份
#      XG-040G-MD 固件时发现它是拿 1710.config 手工改设备 + 追加 PON 全家桶
#      编出来的 —— 私人定制, 仓库里没有对应的公开 config。
#      2010.config (XG2010G) 里 kmod-airoha-{en7572,pon-frontend,xpon} /
#      airoha-pon{ctl,d,debug} / luci-app-onu 全是 =y, 且
#      CONFIG_TARGET_MULTI_PROFILE 已经是 not set —— 拿它改设备,
#      比拿 1710 再补一堆 PON 包干净得多。
# ---------------------------------------------------------------
if ! grep -q '^define Device/nokia_xg-040g-md-ubi' target/linux/airoha/image/an7581.mk 2>/dev/null; then
  echo "FATAL: an7581.mk 里没有 nokia_xg-040g-md-ubi 设备定义, 换设备无从下手"
  exit 1
fi
echo "=== 设备定义存在: nokia_xg-040g-md-ubi ==="

# ---------------------------------------------------------------
# 3. lan1 (2.5G) 冷启动不开链修复 —— EN8811H 复位时序
#
#    现象: lan1(2.5G) 冷启动起不来, 必须 `ip link set lan1 down/up` 才通;
#          拔插网线救不回来。
#    根因: en8811 节点的 reset-assert-us / reset-deassert-us 值。
#          airoha_eth 是 builtin, 内核初始化阶段就把 MAC+PCS bring-up 完了,
#          PHY 复位由 phylib 在 en8811h probe 之后执行, 晚于 MAC 侧 ——
#          1s 的复位时间让 SoC 侧 PCS 起来时对端还被摁在复位线上,
#          rxlock 拿不到训练序列 -> 链路"假 Up"(ethtool 全绿但 RX 几乎为 0)。
#    修法: 改成主线一致的 10ms/20ms。DTS 是纯文本, 不需要碰补丁机制。
#
#    实测本 fork @8243d9a5 的当前值 (an7581-nokia_xg-040g-md-common.dtsi:165):
#        reset-assert-us   = <1000000>   (1s)
#        reset-deassert-us = <100000>    (100ms)
#      -> **这个 fork 没有合入上游那个修复** (溯源自 naoki66 的 XG-040G-MD
#         固件解出的 DTB 也是 1s/100ms, 与此处一致), 所以本段不是 no-op。
#
#    幂等: 上游哪天自己修了就走"跳过"分支, 不会把构建判死。
# ---------------------------------------------------------------
DTS_XG=target/linux/airoha/dts/an7581-nokia_xg-040g-md-common.dtsi
if [ ! -f "$DTS_XG" ]; then
  echo "FATAL: 找不到 $DTS_XG, lan1 复位时序修复无法应用"
  exit 1
fi

GOOD_ASSERT='reset-assert-us = <10000>;'
GOOD_DEASSERT='reset-deassert-us = <20000>;'
if grep -qF "$GOOD_ASSERT" "$DTS_XG" && grep -qF "$GOOD_DEASSERT" "$DTS_XG"; then
  echo "=== [跳过] 上游已内置 EN8811H 复位时序修复 (10ms/20ms) ==="
else
  echo "=== 本地改回主线值 1s/100ms -> 10ms/20ms ==="
  for pair in \
    'reset-assert-us = <1000000>;|reset-assert-us = <10000>;' \
    'reset-deassert-us = <100000>;|reset-deassert-us = <20000>;'
  do
    O=$(printf '%s' "$pair" | cut -d'|' -f1)
    N=$(printf '%s' "$pair" | cut -d'|' -f2)
    C=$(grep -cF "$O" "$DTS_XG" 2>/dev/null || true)
    if [ "$C" != "1" ]; then
      echo "FATAL: $DTS_XG 中 '$O' 出现 $C 次 (期望恰好 1 次), 拒绝盲改"
      grep -nF "$O" "$DTS_XG" || true
      exit 1
    fi
    # 不用 sed -i.bak: 会在 dts 目录里留下 .bak, 可能被 Makefile 的通配扫进去
    TMP_DTS="$DTS_XG.tmpfix"
    sed "s|$O|$N|" "$DTS_XG" > "$TMP_DTS"
    if [ "$(wc -l < "$DTS_XG")" != "$(wc -l < "$TMP_DTS")" ]; then
      echo "FATAL: $DTS_XG 替换后行数变了, 拒绝写回"
      rm -f "$TMP_DTS"
      exit 1
    fi
    mv "$TMP_DTS" "$DTS_XG"
    if grep -qF "$O" "$DTS_XG"; then
      echo "FATAL: sed 替换失败, 旧值还在: $O"
      exit 1
    fi
  done
  sed -i 's|Hold reset for 1 second and wait 100 ms before probing EN8811H\.|Hold reset for 10 ms and wait 20 ms before probing EN8811H.|' "$DTS_XG"
  echo "=== EN8811H 复位时序已改回主线值 (1s/100ms -> 10ms/20ms) ==="
fi
grep -nE "reset-(assert|deassert)-us|Hold reset for" "$DTS_XG"

# ---------------------------------------------------------------
# 4. firewall4: 让 flowtable 也能认 zone 里 "list device" 挂的设备
#
#    来源: naoki66 的 pon_userspace 仓库 patches/firewall4/, 与 luci-app-onu
#    同源。解决: PPPoE 在本机终结时 l3_device=pppoe-wan、devtype=ppp,
#    resolve_lower_devices **不往 ppp 底下递归** -> 下面那层 802.1q 上联和
#    物理口(pon0)永远进不了 flowtable -> PPE 硬件卸载不生效, 全走软转发。
#    对 luci-app-onu 上网页的「PPE flowtable 硬件卸载」开关是配套项 ——
#    只装 luci-app-onu 不打这个, 那个开关开了也没用。
#
#    ⚠️ 这个补丁**不会**被源码树自带的 apply-feed-patches.sh 应用 ——
#       那个脚本只处理源码树的 patches/feeds/<feed>/ 目录, 用
#       `git -C feeds/<feed> apply` 打到 feed 仓库里; firewall4 是源码树内
#       的包 (package/network/config/firewall4), 不在任何 feed 下。
#       所以只能靠本脚本把它放进 firewall4 的 patches/ 走 quilt。
#
#    ⚠️ 上游原版**打不上**: 它基于未打本地补丁的 fw4.uc, hunk 1 尾部上下文
#       是 "空行 + return {"; 而本树自带的 fullcone 补丁在 nft_try_hw_offload
#       之后插入了 nft_try_fullcone(), 把那段上下文从中间劈开 ->
#       实测 `patch -p1` 报 "does not apply" at fw4.uc:489。
#       OpenWrt-Actions 里这份已 rebase (只挪函数位置, 逻辑逐字一致)。
#       已用真 `patch -p1` 按序验证: 001-fullcone -> 001-bridge -> 010-zone 全 OK。
#
#    版本核对: 本 fork 的 firewall4 是 PKG_SOURCE_DATE=2025-03-17 /
#       PKG_SOURCE_VERSION=b6e5157527d361f99ad52eaa6da273cb0f2dfd59,
#       与 pbs05/ponwrt 那条线**同一个提交**, 已有的两个 001 补丁也基本同源
#       (fullcone 那份逐字节相同; bridge-flowtable 那份有差异, 但已实测
#       三个补丁按序应用仍然全 OK)。
# ---------------------------------------------------------------
FW4_PATCH_DIR=package/network/config/firewall4/patches
if [ ! -d "$FW4_PATCH_DIR" ]; then
  echo "FATAL: 找不到 $FW4_PATCH_DIR, firewall4 flowtable 补丁无处安放"
  exit 1
fi

FW4_SRC="${GITHUB_WORKSPACE:-..}/patches/firewall4/010-fw4-zone-device-flowtable.patch"
if [ ! -e "$FW4_SRC" ]; then
  echo "FATAL: 找不到 $FW4_SRC"
  exit 1
fi
cp "$FW4_SRC" "$FW4_PATCH_DIR/010-fw4-zone-device-flowtable.patch"

# 断言: 只准存在一份, 别把两个版本的同名补丁叠在一起 (quilt 会重复应用 -> 失败)
FW4_N=$(ls -1 "$FW4_PATCH_DIR" | grep -c 'fw4-zone-device-flowtable' || true)
if [ "$FW4_N" != "1" ]; then
  echo "FATAL: $FW4_PATCH_DIR 里 fw4-zone-device-flowtable 补丁有 $FW4_N 份 (期望 1)"
  ls -1 "$FW4_PATCH_DIR"
  exit 1
fi
echo "=== firewall4 flowtable 补丁已就位 (zone.device -> 软硬件卸载路径) ==="
ls -1 "$FW4_PATCH_DIR"

exit 0
