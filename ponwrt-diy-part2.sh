#!/bin/bash
# DIY 后置脚本: 完全按 PonWrt 官方 CI 的方式组装配置
#   1) kconfig.pl 合并 configs/an7581.config + configs/release.config (官方方法)
#   2) 追加只编 Nokia XG-040G-MD (UBI) 的设备选择 (纯追加, 不做 sed 手术)
#   3) 追加自定义附加包 (ponwrt-extra.config)
#   4) make defconfig 展开
#   5) 一组 defconfig 之后的硬校验 (关键驱动 / 指定包含 / 已砍包不许复活 /
#      DEBUG_INFO / ccache) —— 全部在 40 秒内出结果, 不用白编 3.5 小时

set -e

# ---------------------------------------------------------------
# 诊断工具: 失败原因必须发成 GitHub 注解
#
# 为什么不能只 echo: GitHub 公开仓库的**完整 job 日志需要 admin 权限**
#   (匿名读 API 是 403 "Must have admin rights", 网页版也要求登录),
#   而 **check-run 的 annotations 是匿名可读的**。
#   配置阶段的失败只 echo 的话, 排障就只能靠人肉贴日志 —— 差一个数量级。
# 注解里换行必须编码成 %0A, % 本身要先转义成 %25 (GitHub workflow command 规则)。
# 注意: 发 ::error:: 不会改变步骤退出码, 只挂注解; 失败仍靠下面的 exit 1。
# ---------------------------------------------------------------
esc() { local s="${1//%/%25}"; printf '%s' "${s//$'\n'/%0A}"; }
NL=$'\n'
err() { echo "::error::$(esc "$1")"; printf '%s\n' "$1"; }

# 1. 官方合并方式 (与 .github/workflows/release.yml 一致)
./scripts/kconfig.pl + \
  configs/an7581.config \
  configs/release.config > .config

# 2. 设备选择 + 必须关掉 MULTI_PROFILE
#
#    官方 configs/an7581.config 第 58 行带 CONFIG_TARGET_MULTI_PROFILE=y,
#    会把该 target 下全部 ~13 个设备都编一遍。三个后果:
#      a) 编译从 ~1h 涨到 ~2h50m;
#      b) 产物里混进一堆无关设备的镜像;
#      c) .config 里出现多个 CONFIG_TARGET_DEVICE_*=y, 编译步骤把
#         DEVICE_NAME 写进 $GITHUB_ENV 时变成多行, runner 直接报
#         "Invalid format '<第二行>'" 并把整个编译步骤打失败 (run #15 就是这么挂的,
#         校验步骤根本没跑到)。
#
#    怎么关: scripts/target-metadata.pl:242 里 TARGET_MULTI_PROFILE 与
#    legacy 的 TARGET_<conf>_<profile> 同在一个 choice 中(互斥),
#    显式选中 legacy 符号即可把它顶掉。两个符号形态都要写:
#      - CONFIG_TARGET_airoha_an7581_DEVICE_<profile>        legacy, 在 choice 里
#      - CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_<profile> 新版 menuconfig 符号
#        (由 scripts/target-metadata.pl:314 生成, 只在 MULTI_PROFILE 下用于多选)
cat >> .config << 'EOF'
# CONFIG_TARGET_MULTI_PROFILE is not set
CONFIG_TARGET_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y
CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y
EOF

# 3. 追加自定义附加包 (OpenClash/DDNS/中文/WireGuard 等)
[ -e "$GITHUB_WORKSPACE/$CONFIG_FILE" ] && cat "$GITHUB_WORKSPACE/$CONFIG_FILE" >> .config

# 4. 展开为完整配置
make defconfig

# 诊断 (2026-10-06): 无论后面哪条断言炸, 先把相关符号的**真实值**发成注解。
# 这样一次运行就能定位, 不用"改一点推一次"地猜。
# 注意: 这里**只观测不断言**。省下的这点时间不值得拿一次 1.5~3 小时的构建去赌
# 一条硬断言 (ppp 那三个包就是教训) —— 关没关掉看注解即可。
# 2026-10-06 追加: WiFi 全家桶 / 冗余 PHY / hwmon / i2c-core 同样只观测,
#   因为 feeds 里的 luci-app-* 有可能 DEPENDS wpad 把它们 select 回来。
SYMS="$(grep -aE 'shellsync|kmod-macvlan|luci-app-iptv|iptv-zh-cn|kmod-mppe|ovpn-backports|libi2c|i2c-tools|i2c-core|hwmon-core|mt76|mt791|cfg80211|mac80211|PACKAGE_wpad|PACKAGE_hostapd|wireless-regdb|wifi-scripts|nl80211|PACKAGE_iw=|zn515|phy-realtek|phy-maxlinear|rtl826x|KERNEL_DEBUG|CCACHE|CONFIG_DEVEL|COLLECT_KERNEL_DEBUG' .config | sort -u || true)"
echo "::warning::$(esc "defconfig 之后的相关符号实况:${NL}${SYMS}")"

# 早失败: MULTI_PROFILE 若还开着, 后面会白编两个多小时, 而且编译步骤
# 写 $GITHUB_ENV 时会因为多行直接被打失败。这里几十秒内就拦住。
if grep -q '^CONFIG_TARGET_MULTI_PROFILE=y' .config; then
  echo "FATAL: CONFIG_TARGET_MULTI_PROFILE 仍为 y, 会编译全部设备"
  echo "       (产物混杂 + 编译步骤 DEVICE_NAME 多行导致 runner 报 Invalid format)"
  grep '^CONFIG_TARGET.*DEVICE.*=y' .config | head -20 || true
  err "FATAL: CONFIG_TARGET_MULTI_PROFILE 仍为 y (会编译全部设备)"
  exit 1
fi
echo "=== MULTI_PROFILE 已关闭, 单设备构建 ==="

echo "=== 已选设备 ==="
grep '^CONFIG_TARGET.*DEVICE.*=y' .config || true
echo "=== PON 相关包 ==="
grep -E 'PON|PONCTL|POND|XPON|ponctl|pond' .config | grep '=y' | head -20 || true
echo "=== 2.5G PHY 相关 ==="
grep -E 'en8811|EN8811' .config | grep '=y' || true

# 强校验: 关键硬件驱动缺失则构建失败 (避免产出 PON/2.5G 口失效的固件)
MISSING=""
for pkg in kmod-airoha-en7572 kmod-phy-airoha-en8811h kmod-airoha-xpon kmod-airoha-pon-frontend \
           airoha-en8811h-firmware airoha-en7581-npu-firmware \
           airoha-ponctl airoha-pond luci-app-pon ; do
  grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || MISSING="$MISSING $pkg"
done
if [ -n "$MISSING" ]; then
  echo "FATAL: 关键硬件驱动未进入配置:$MISSING"
  err "FATAL: 关键硬件驱动未进入配置:$MISSING"
  exit 1
fi
echo "=== 关键驱动校验通过 ==="

# 强校验: 用户显式要求的包必须在 defconfig 之后还活着。
# 为什么必须查: make defconfig 对不存在的 CONFIG_PACKAGE_xxx 符号的处理就是
#   —— 默默删掉那一行。编译照 green, 固件里就是没有。run #16 的 openclash
#   就是这么失踪的 (固定的 luci/packages feed 里压根没这个包)。这里几十秒挡住,
#   省得白编两小时再靠 manifest 反查。
for pkg in luci-app-openclash luci-app-adblock-fast ; do
  if ! grep -q "^CONFIG_PACKAGE_${pkg}=y" .config; then
    echo "FATAL: ${pkg} 在 defconfig 之后不是 =y —— 大概率是 feeds 里没这个包"
    echo "       luci pin 落在 ed0441b1(2026-10-02 merge) 之前的话, openclash 等"
    echo "       第三方 LuCI 应用是不存在的; 另外确认 scripts/feeds install -a 跑过"
    err "FATAL: ${pkg} 在 defconfig 之后不是 =y (feeds 里没这个包?)"
    exit 1
  fi
done
echo "=== 指定包含的包全部命中: openclash / adblock-fast ==="

# 强校验: 明确砍掉的包不许复活 (2026-10-06 编译耗时优化)。
#
# ⚠️ 这里**只列真正砍得掉的包**。run #26 的注解实测纠正了一个误判, 记下来免得再犯:
#
#   shellsync / kmod-macvlan / kmod-mppe 关不掉, 因为它们是 ppp 的硬依赖 →
#
#     package/network/services/ppp/Makefile:56   Package/ppp DEPENDS:= ... +shellsync +kmod-mppe
#     package/network/services/shellsync/Makefile:12  Package/shellsync DEPENDS:=+libpthread +kmod-macvlan
#
#   而 ppp 又是目标默认包 (include/target.mk:52 DEFAULT_PACKAGES.router 含 ppp + ppp-mod-pppoe),
#   由 scripts/target-metadata.pl:262 生成 `select DEFAULT_ppp` → package-metadata.pl:355 的
#   `default y if DEFAULT_<pkg>` 直接把 PACKAGE_ppp 顶成 y, 再经 scripts/package-metadata.pl
#   mconf_depends() 的 `$m = "select"` 把 `+shellsync` / `+kmod-mppe` / `+kmod-macvlan`
#   全部升成 `select PACKAGE_xxx`。
#
#   结论: select 优先级高于用户写的 `# ... is not set`, 写多少遍都没用。
#   要真关掉只能改 ppp 的 Makefile —— 那等于砍掉 PPPoE 的 MPPE 加密与多拨同步, 不做。
#   收益本就以秒计 (shellsync 是单个 .c, 两个各一个 .ko), 不值得为它动核心包。
#
#   luci-app-iptv(+i18n) / kmod-ovpn-backports 则确实无人 select (iptv 只被本仓 extra.config 打开;
#   kmod-ovpn-backports 的上游 select 源是 openvpn, 而 openvpn 未启用) —— 实测已成功关闭。
FORBID_PKG_LIST="luci-app-iptv luci-i18n-iptv-zh-cn kmod-ovpn-backports"
FORBID_PKG_RE="luci-app-iptv|luci-i18n-iptv-zh-cn|kmod-ovpn-backports"
HIT=""
for pkg in $FORBID_PKG_LIST; do
  if grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || grep -q "^CONFIG_PACKAGE_${pkg}=m" .config; then
    HIT="$HIT $pkg"
  fi
done
if [ -n "$HIT" ]; then
  echo "FATAL: 已砍掉的包又冒出来了:$HIT"
  echo "       多半是别的包 DEPENDS/select 它们; =m 也算(照样编译, 只是不进镜像)。"
  grep -E "^CONFIG_PACKAGE_(${FORBID_PKG_RE})=" .config || true
  err "FATAL: 已砍掉的包又冒出来了:$HIT${NL}$(grep -E "^CONFIG_PACKAGE_(${FORBID_PKG_RE})=" .config || true)"
  exit 1
fi
echo "=== 已砍包确认全部关闭: luci-app-iptv(+i18n) / kmod-ovpn-backports ==="
echo "=== (shellsync / kmod-macvlan / kmod-mppe 是 ppp 的硬依赖, 保留, 见上方注释) ==="

# 强校验: 内核与全部 kmod 不再产 DWARF 调试信息 (编译时间 + 磁盘)
if grep -qE "^CONFIG_KERNEL_DEBUG_INFO(_REDUCED)?=y" .config; then
  echo "FATAL: CONFIG_KERNEL_DEBUG_INFO 仍是 y —— 内核与全部 kmod 会全带调试信息"
  echo "       extra.config 里的反向覆盖没生效? 确认没有别的文件在它后面又打开了。"
  grep -nE "^CONFIG_KERNEL_DEBUG_INFO" .config || true
  err "FATAL: CONFIG_KERNEL_DEBUG_INFO 仍是 y${NL}$(grep -nE "^CONFIG_KERNEL_DEBUG_INFO" .config || true)"
  exit 1
fi
echo "=== 内核 DEBUG_INFO 已关闭 (DEBUG_FS 保留) ==="

# 强校验: ccache 真的开着 (否则 workflow 的 Cache ccache 步骤白存 1.5 GB)
if ! grep -q "^CONFIG_CCACHE=y" .config; then
  echo "FATAL: CONFIG_CCACHE 不是 y —— ccache 缓存白存, 编译也不会变快"
  err "FATAL: CONFIG_CCACHE 不是 y${NL}$(grep -nE "^CONFIG_(CCACHE|DEVEL)" .config || true)"
  exit 1
fi
echo "=== ccache 已启用 (CCACHE_DIR 由 workflow 指定并缓存) ==="

# 强校验: UPnP 必须真的关掉。官方 configs/release.config 自带
# CONFIG_PACKAGE_luci-app-upnp=y, 只在 ponwrt-extra.config 里删掉那一行没用,
# 必须写 "# ... is not set" 反向覆盖。这里确认覆盖真生效了。
UPNP_ON="$(grep -E '^CONFIG_PACKAGE_(luci-app-upnp|luci-i18n-upnp-zh-cn|miniupnpd-nftables|miniupnpd-iptables)=y' .config || true)"
if [ -n "$UPNP_ON" ]; then
  echo "FATAL: UPnP 组件仍然开着 (release.config 的 base 值没覆盖掉):"
  printf '%s\n' "$UPNP_ON"
  err "FATAL: UPnP 组件仍然开着:${NL}${UPNP_ON}"
  exit 1
fi
echo "=== UPnP 已确认关闭 ==="

# 提醒: /etc/config/pon 的 schema 随 pon_userspace 演进 (huawei_compat 已改名
# disable_enhanced_security, 新增 registration_id/loid_password)。刷机后不要
# 恢复旧固件的 /etc/config/pon, 否则密码(PLOAM Registration-ID)字段缺失,
# PON 无法注册。
echo "=== 提醒: 不要恢复旧固件的 /etc/config/pon (schema 已变更) ==="
