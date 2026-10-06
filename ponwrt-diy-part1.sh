#!/bin/bash
# DIY 前置脚本（feeds 更新前执行）
# PonWrt 的 feeds.conf.default 已自带 PON 驱动/用户态源，无需额外添加。
# luci-app-openclash 走 immortalwrt/luci 自带的 applications/luci-app-openclash。
#   前提: luci feed 必须 pin 在 ed0441b1 (2026-10-02 "Merge Official Source") 或之后 ——
#   之前的提交里这批第三方 LuCI 应用被整段拆走了 (详见 ponwrt-feeds.conf 注释)。
#   openclash 缺包时在 extra.config 写 =y 毫无用处: defconfig 会静默删符号。

# ---------------------------------------------------------------
# 清掉 dl 缓存里被还原出来的 go-mod-cache (run #18 学来的教训)
#
# 症状: yq (Go 包) 三次 make (j / j1 / V=s) 都失败, 报一堆长得一模一样的错:
#     no required module provides package github.com/zclconf/go-cty/cty/internal/graphemes
#     no required module provides package github.com/google/go-cmp/cmp/internal/flags
#     no required module provides package github.com/pkg/diff/intern
#     build constraints exclude all Go files in .../go-isatty@v0.0.20
#   而那些文件在磁盘上明明存在 —— 说明 Go 的 module loader 看不到它们。
#
# 成因两条:
#   1) 缓存是由 actions/cache 的 restore-key 兜底还原出来的 (改了 feeds.conf
#      主 key 没命中), 提取出来的 module 目录残缺/缺 cache/download 元数据;
#   2) 构建期 Go 是离线跑的 (GOPROXY=off), 日志里连一条 "go: downloading"
#      都没有, 缺东西不会去补, 直接判失败 —— 所以重试多少次都必然复现。
#
# 处理: 删掉让它重新下载。放在这里 (feeds update / make download 之前) 最合适:
#   下载阶段有网, 补回来就行; 代价只是多花几分钟, 比重做整个 dl 缓存便宜。
# ---------------------------------------------------------------
for d in "$PWD/dl/go-mod-cache" /workdir/openwrt/dl/go-mod-cache; do
  if [ -d "$d" ]; then
    echo "删除还原出来的 go-mod-cache: $d (不可信, 见脚本注释)"
    rm -rf "$d"
  fi
done

# ---------------------------------------------------------------
# LAN 口 QoS 通道修复 (2026-10-06 v7 定案, lan2/lan3 卡 500M)
#
# 症状: lan2 / lan3 上网被卡在 ~500 Mbps, lan4 满速 1000, lan1(2.5G) 满速。
#       到网关速率正常 —— 因为到网关是本机 CPU 发包, 走的是另一条选通道路径。
#
# 根因 (实测定案, 不是推测):
#   airoha_ppe.c 的 FOE 入口按 DSA 端口号选 QDMA QoS 通道:
#       channel = dsa_port >= 0 ? dsa_port : port->id;
#       channel = channel % AIROHA_NUM_QOS_CHANNELS;   /* 4 */
#   => lan2 -> 通道 2, lan3 -> 通道 3, lan4 -> 通道 0, lan1 -> 通道 0, 通道 1 空置。
#
#   AN7581 上通道 0 实测能跑满: E5 实验 (客户端插在 lan1) 1 秒峰值 119,638 pps,
#   同秒 lan1.tx_bytes = 182.38 MB/s = 1459 Mbps, corr(ch0, lan1.tx_bytes)=0.999。
#   而通道 2/3 在单口独占、无任何竞争时也只有 ~500 Mbps
#   (E1: 客户端在 lan3, ch3 1s 峰值 47,628 pps ≈ 571 Mbps, 同秒 ch0 仅 1 pps)。
#   lan4 之所以一直满速, 就是因为它 (4%4=0) 恰好落在通道 0。
#
#   已排除的方向: TRTCM 令牌桶表用读事务整表读完 = 全 0; TXQ close 全开;
#   CHAN_QOS_MODE=0x11111111 全 SP; 用户态/openclash 无关。详见工作区报告
#   《lan2-4-只有一个口跑满-根因分析.md》与 Obsidian《...根因定位》笔记。
#
# 修法: 让所有 DSA 目标端口的 FOE 入口统一走通道 0 (已经实测证明最快的那条)。
#   只改 158 号补丁里那一行的右值, 行数完全不变 ->
#   后面 915-02 补丁把那两行当 context, 依旧能干净应用, 不用动它。
#
# 注意: 158 是**上游主线补丁**(Lorenzo Bianconi, netdev, acked by Jakub Kicinski,
#   提交说明原话 "This allows HTB shaping to be applied to HW accelerated
#   traffic"), ImmortalWrt 主线 r41341 里同样存在 ->
#   **这不是 PonWrt 独有的差异**, 两条主线一样中招, 所以只能在本地再叠一层修正。
# ---------------------------------------------------------------
P158=$(ls target/linux/airoha/patches-6.18/158-*.patch 2>/dev/null | head -1)
if [ -z "$P158" ]; then
  echo "FATAL: 找不到 target/linux/airoha/patches-6.18/158-*.patch"
  echo "       LAN 口 QoS 通道修复无法应用, 中止 (不要产出没有修复的固件)"
  exit 1
fi

OLD_LINE='channel = dsa_port >= 0 ? dsa_port : port->id;'
NEW_LINE='channel = dsa_port >= 0 ? 0 : port->id;'

# 唯一性断言: 不是刚好 1 处就拒绝盲改 (上游改结构时会在这里拦住)
CNT=$(grep -cF "$OLD_LINE" "$P158" 2>/dev/null || true)
if [ "$CNT" != "1" ]; then
  echo "FATAL: $P158 中 '$OLD_LINE' 出现 $CNT 次 (期望恰好 1 次)"
  grep -nF "$OLD_LINE" "$P158" || true
  exit 1
fi

echo "--- 修改前 ---"
grep -nF "$OLD_LINE" "$P158"
sed -i.bak "s|$OLD_LINE|$NEW_LINE|" "$P158"
if grep -qF "$OLD_LINE" "$P158"; then
  echo "FATAL: sed 替换失败, $P158 里旧行还在"
  exit 1
fi
echo "--- 修改后 ---"
grep -nF "$NEW_LINE" "$P158"
echo "=== LAN 口 QoS 通道修复已注入: DSA 目标端口全部走通道 0 ==="
echo "=== (lan2/lan3 由通道 2/3 改到通道 0; lan1/lan4 本来就是通道 0, 不受影响) ==="

# ---------------------------------------------------------------
# lan1 (2.5G) 冷启动不开链修复 —— EN8811H 复位时序
#
# 现象: 刷 PonWrt 后 lan1(2.5G) 冷启动起不来, 必须 `ip link set lan1 down/up`
#       复位一次才通; 拔插网线救不回来。刷 ImmortalWrt 没这个问题。
#
# 根因 (离线固件解包 + 源码层按 ref 直取, 双证):
#   target/linux/airoha/dts/an7581-nokia_xg-040g-md-common.dtsi
#     en8811: ethernet-phy@f  (compatible = "ethernet-phy-id03a2.a411")
#       PonWrt      @5651948f9d : reset-assert-us = <1000000> (1s)
#                                 reset-deassert-us = <100000> (100ms)   <-- pin 的 ref 里就是这个
#       ImmortalWrt @f44d1535b4 : reset-assert-us = <10000>   (10ms)
#                                 reset-deassert-us = <20000>   (20ms)
#   两个文件都按 ref 直取核对过 (HTTP 200), 同一节点只差这两个值。
#
#   机制: airoha_eth 是 builtin, 内核初始化阶段就把 MAC+PCS bring-up 完了;
#   PHY 复位由 phylib 在 en8811h probe 之后执行, 晚于 MAC 侧。
#   2500BASE-X 是 MAC<->PHY 带内自协商, SoC 侧 PCS 起来时对端还被摁在复位线上
#   -> rxlock 拿不到训练序列 -> 链路"假 Up"(ethtool 全绿, 但 RX 几乎为 0)。
#   down/up 会重跑 MAC+PCS+DMA ring, 所以能救; 拔插只 flap PHY 层, 救不回来。
#
# 修法: 改回主线一致的 10ms/20ms。DTS 是纯文本, 不需要碰补丁机制。
#       只改内容不改行数, 注释也一起改。
# ---------------------------------------------------------------
DTS_XG=target/linux/airoha/dts/an7581-nokia_xg-040g-md-common.dtsi
if [ ! -f "$DTS_XG" ]; then
  echo "FATAL: 找不到 $DTS_XG, lan1 复位时序修复无法应用"
  exit 1
fi

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
  sed -i.bak "s|$O|$N|" "$DTS_XG"
  if grep -qF "$O" "$DTS_XG"; then
    echo "FATAL: sed 替换失败, 旧值还在: $O"
    exit 1
  fi
done

# 注释跟着改 (同样只改内容不改行数)
sed -i 's|Hold reset for 1 second and wait 100 ms before probing EN8811H\.|Hold reset for 10 ms and wait 20 ms before probing EN8811H.|' "$DTS_XG"

echo "=== EN8811H 复位时序已改回主线值 (1s/100ms -> 10ms/20ms) ==="
grep -nE "reset-(assert|deassert)-us|Hold reset for" "$DTS_XG"

exit 0
