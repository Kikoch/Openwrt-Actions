#!/bin/bash
# ============================================================
# ONU 编译线 DIY 后置脚本（feeds install 之后、编译之前执行）
#
#   1) cp 2010.config .config        —— 该 fork 的官方做法 (照抄它的 workflow)
#   2) 追加: 设备从 gemtek_xg2010g-ubi 换成 nokia_xg-040g-md-ubi
#   3) 追加: onu-extra.config (包选择, 沿用 ponwrt 线那套需求清单)
#   4) set-build-version.sh          —— 该 fork 自带的版本串生成
#   5) make defconfig 展开
#   6) 一组 defconfig 之后的硬校验
#
# ⚠️ 与 ponwrt-diy-part2.sh 的差异 —— 不要照抄那条线的合并方式:
#     那条线: scripts/kconfig.pl + configs/an7581.config + configs/release.config
#     本线:   cp 2010.config .config   (本 fork 没有 configs/an7581.config,
#             它的 configs/ 里只有一个 11 行的 release.config; 种子配置放在
#             仓库根目录: 1710.config / 2010.config / 2010-2g.config)
#
# ⚠️ 本线**不跑** scripts/check-gemtek-profile-isolation.sh:
#     那个脚本只认 gemtek_xr1710g / gemtek_xg2010g 两个 profile, 走到 else
#     分支是 `echo "unsupported Gemtek profile" && exit 1` —— 我们改成 nokia
#     设备后必然被它判死。它是给 Gemtek 设备做 profile 隔离用的, 与本线无关。
# ============================================================

set -e

# ---------------------------------------------------------------
# 诊断工具: 失败原因必须发成 GitHub 注解
#   GitHub 公开仓库的**完整 job 日志需要 admin 权限**, 而 check-run 的
#   annotations 是匿名可读的。配置阶段的失败只 echo 的话, 排障要人肉贴日志。
#   注解里换行必须编码成 %0A, % 本身要先转义成 %25。
# ---------------------------------------------------------------
esc() { local s="${1//%/%25}"; printf '%s' "${s//$'\n'/%0A}"; }
NL=$'\n'
err() { echo "::error::$(esc "$1")"; printf '%s\n' "$1"; }

# 1. 用 2010.config 做种子（该 fork 的官方做法）
cp 2010.config .config

# 2. 设备切换: gemtek_xg2010g-ubi -> nokia_xg-040g-md-ubi
#
#    2010.config 里相关的三行 (实测):
#      57: # CONFIG_TARGET_MULTI_PROFILE is not set          <- 已经是 not set, 很好
#      67: CONFIG_TARGET_airoha_an7581_DEVICE_gemtek_xg2010g-ubi=y
#      73: CONFIG_TARGET_PROFILE="DEVICE_gemtek_xg2010g-ubi"
#    没有 CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_* 那一行 —— 那个符号只在
#    MULTI_PROFILE 下用于多选, 这里 MULTI_PROFILE 是关的, 所以不存在。
#    但显式写上不影响 (PonWrt 线也是两个形态都写)。
#
#    为什么 CONFIG_TARGET_PROFILE 也要改:
#      scripts/set-build-version.sh 从它推导设备型号写进 VERSION_DIST
#      (DEVICE_gemtek_xg2010g-ubi -> 去 gemtek_ 前缀、去 -ubi 后缀 -> XG2010G)。
#      不改的话版本串会显示成 "ImmortalWrt naoki66 XG2010G" 而产物其实是
#      Nokia —— naoki66 自己那份 XG-040G-MD 固件就是这么串的 (显示 XR1710G)。
#      改成 DEVICE_nokia_xg-040g-md-ubi 后串为 NOKIA_XG-040G-MD。
cat >> .config << 'EOF'
# CONFIG_TARGET_MULTI_PROFILE is not set
# CONFIG_TARGET_airoha_an7581_DEVICE_gemtek_xg2010g-ubi is not set
CONFIG_TARGET_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y
CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y
CONFIG_TARGET_PROFILE="DEVICE_nokia_xg-040g-md-ubi"
EOF

# 3. 追加自定义附加包
[ -e "$GITHUB_WORKSPACE/$CONFIG_FILE" ] && cat "$GITHUB_WORKSPACE/$CONFIG_FILE" >> .config

# 4. 版本串（该 fork 自带; 环境变量由 workflow 提供, 缺失时用兜底值）
if [ -x scripts/set-build-version.sh ]; then
  BUILD_DATE="${BUILD_DATE:-$(date +%Y%m%d)}" \
  BUILD_ID="${BUILD_ID:-${BUILD_DATE:-$(date +%Y%m%d)}-local}" \
  REPO_COMMIT="${REPO_COMMIT:-local}" \
  UPSTREAM_COMMIT="${UPSTREAM_COMMIT:-local}" \
  VERSION_CODE="${VERSION_CODE:-${BUILD_ID:-local}}" \
  bash scripts/set-build-version.sh .config
  echo "=== 版本串已生成 ==="
  grep -E '^CONFIG_VERSION_(DIST|NUMBER|CODE)=' .config || true
else
  echo "::warning::scripts/set-build-version.sh 不存在, 跳过版本串生成"
fi

# 5. 展开为完整配置
make defconfig

# 诊断: 无论后面哪条断言炸, 先把相关符号的**真实值**发成注解
SYMS="$(grep -aE 'luci-app-onu|onu-zh-cn|omcproxy|airoha-pon|kmod-airoha|luci-app-openclash|luci-app-upnp|luci-theme|KERNEL_DEBUG|CCACHE|CONFIG_DEVEL|PACKAGE_zram|PACKAGE_kmod-zram|luci-proto-wireguard|luci-i18n-ddns|MULTI_PROFILE|TARGET_PROFILE' .config | sort -u || true)"
echo "::warning::$(esc "defconfig 之后的相关符号实况:${NL}${SYMS}")"

# ---------------------------------------------------------------
# 强校验 1: 设备必须真的是 nokia_xg-040g-md-ubi, 且 MULTI_PROFILE 关着
# ---------------------------------------------------------------
if grep -q '^CONFIG_TARGET_MULTI_PROFILE=y' .config; then
  err "FATAL: CONFIG_TARGET_MULTI_PROFILE 仍为 y, 会编译全部设备"
  exit 1
fi
if ! grep -q '^CONFIG_TARGET_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y' .config; then
  err "FATAL: CONFIG_TARGET_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi 不是 y${NL}$(grep -E '^CONFIG_TARGET.*DEVICE.*=y' .config || true)"
  exit 1
fi
if grep -q '^CONFIG_TARGET_airoha_an7581_DEVICE_gemtek_xg2010g-ubi=y' .config; then
  err "FATAL: gemtek_xg2010g-ubi 还开着 —— 反向覆盖没生效"
  exit 1
fi
echo "=== 设备已切换: nokia_xg-040g-md-ubi (MULTI_PROFILE 关闭, xg2010g 已关) ==="
grep -E '^CONFIG_TARGET.*DEVICE.*=y|^CONFIG_TARGET_PROFILE=' .config || true

# ---------------------------------------------------------------
# 强校验 2: PON 全栈 + luci-app-onu 必须在
#   这些在 2010.config 里本来就是 =y, 断言是为了防 defconfig 把它们删掉
#   (feed 没拉到 / 符号不存在的同构坑: 编译绿、页面没有)。
# ---------------------------------------------------------------
MISSING=""
for pkg in kmod-airoha-xpon kmod-airoha-pon-frontend kmod-airoha-en7572 \
           airoha-ponctl airoha-pond airoha-pon-debug \
           luci-app-onu luci-i18n-onu-zh-cn omcproxy \
           kmod-phy-airoha-en8811h airoha-en8811h-firmware \
           airoha-en7581-npu-firmware ; do
  grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || MISSING="$MISSING $pkg"
done
if [ -n "$MISSING" ]; then
  err "FATAL: PON 相关包未进入配置:$MISSING${NL}多半是 pon_userspace / pon_drivers feed 没拉到"
  exit 1
fi
echo "=== PON 全栈 + luci-app-onu + omcproxy 全部命中 ==="

# ---------------------------------------------------------------
# 强校验 3: 需求包 (沿用 ponwrt 线那套: OpenClash / DDNS(dnspod) /
#   WireGuard / zram / bootstrap 主题)
#   2010.config 实测基线: openclash -- / ddns =y / dnspod -- /
#     wireguard-tools -- / luci-proto-wireguard -- / zram -- / omcproxy --
#     bootstrap =y / argon =y / upnp =y
#   -> 缺的全靠 onu-extra.config 补, 这里确认补成功了。
# ---------------------------------------------------------------
# 清单来自昨日产物 run #32 的 ponwrt-extra.config (74 个显式 =y), 经本线适配:
#   luci-app-pon -> luci-app-onu / luci-i18n-pon-zh-cn -> luci-i18n-onu-zh-cn
#   luci-app-iptv(+i18n) 删除 (已被吸收进 luci-app-onu)
#   kmod-lib-lzo-rle 删除 (该 fork 无此包)
#   omcproxy 新增 (luci-app-onu 硬依赖)
#
# ⚠️ 这里只断言"服务与功能类"的关键包。kernel 条件依赖类
#   (kmod-lib-lzo / kmod-usb-xhci-hcd / ruby-yaml 等) 不在表内:
#   它们在 2010.config 里查无符号, defconfig 是否保留取决于依赖能否满足,
#   断言它们会把好构建判死。extra.config 里照写 =y, 编出来就有、没有也不致命。
MISSING2=""
for pkg in luci-app-openclash ruby ruby-yaml \
           luci-app-ddns luci-i18n-ddns-zh-cn ddns-scripts-dnspod \
           luci-proto-wireguard wireguard-tools kmod-wireguard \
           zram-swap kmod-zram \
           luci-app-package-manager luci-app-attendedsysupgrade \
           luci-mod-admin-full luci-lib-uqr luci-compat autocore \
           iperf3 tcpdump ethtool-full conntrack \
           bash curl wget-ssl ip-full ip-bridge \
           block-mount kmod-fs-ext4 kmod-fs-exfat kmod-fs-vfat \
           kmod-usb3 kmod-usb-storage \
           luci-theme-bootstrap ; do
  if ! grep -q "^CONFIG_PACKAGE_${pkg}=y" .config; then
    MISSING2="$MISSING2 $pkg"
  fi
done
if [ -n "$MISSING2" ]; then
  err "FATAL: 昨日对齐的需求包在 defconfig 之后不是 =y:$MISSING2${NL}检查 onu-extra.config 与 feeds (openclash / ruby 在 immortalwrt 的 luci 与 packages feed, 上游滚动后可能拿不到)"
  exit 1
fi
echo "=== 昨日对齐的需求包全部命中 (openclash / ruby / ddns / wireguard / zram / 工具集 / USB / bootstrap) ==="

# ---------------------------------------------------------------
# 强校验 4: 已砍掉的包不许复活
#   upnp:   configs/release.config 自带 CONFIG_PACKAGE_luci-app-upnp=y,
#           2010.config 里也是 =y -> 必须反向覆盖。
#   argon:  2010.config:6397 附近是 =y -> 需求是"只留 bootstrap"。
#   adblock: 本线基线本来就没开, 这里写上是防回归。
#   ⚠️ 只列真砍得掉的 —— 不要塞 ppp 的硬依赖 (shellsync / kmod-macvlan /
#      kmod-mppe), select 压过 is not set, 写了必然判死 (ponwrt 线 run #26 教训)。
# ---------------------------------------------------------------
HIT=""
for pkg in luci-app-upnp luci-i18n-upnp-zh-cn miniupnpd-nftables miniupnpd-iptables \
           luci-theme-argon luci-theme-footstrap luci-theme-material \
           luci-theme-openwrt luci-theme-openwrt-2020 \
           luci-app-adblock-fast adblock-fast luci-i18n-adblock-fast-zh-cn ; do
  if grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || grep -q "^CONFIG_PACKAGE_${pkg}=m" .config; then
    HIT="$HIT $pkg"
  fi
done
if [ -n "$HIT" ]; then
  err "FATAL: 已砍掉的包又冒出来了:$HIT${NL}$(grep -E '^CONFIG_PACKAGE_(luci-app-upnp|luci-theme-|adblock)' .config || true)"
  exit 1
fi
echo "=== 已砍包确认关闭: upnp 全家 / argon 等 5 个主题 / adblock 全家 ==="

# ---------------------------------------------------------------
# 强校验 5: 内核与 kmod 不带 DWARF 调试信息 + ccache 真的开着
# ---------------------------------------------------------------
if grep -qE "^CONFIG_KERNEL_DEBUG_INFO(_REDUCED)?=y" .config; then
  err "FATAL: CONFIG_KERNEL_DEBUG_INFO 仍是 y${NL}$(grep -nE '^CONFIG_KERNEL_DEBUG_INFO' .config || true)"
  exit 1
fi
echo "=== 内核 DEBUG_INFO 已关闭 ==="

if ! grep -q "^CONFIG_CCACHE=y" .config; then
  err "FATAL: CONFIG_CCACHE 不是 y —— ccache 缓存白存${NL}$(grep -nE '^CONFIG_(CCACHE|DEVEL)' .config || true)"
  exit 1
fi
echo "=== ccache 已启用 ==="

# ---------------------------------------------------------------
# 提醒
# ---------------------------------------------------------------
echo "=== 提醒: 本线是 naoki66 fork + luci-app-onu, 页面在顶级「ONU」菜单 ==="
echo "=== 提醒: 业务配置为 /etc/config/onu-{internet,iptv,voice}, 不是旧的 {internet,iptv,voice} ==="
echo "=== 提醒: /etc/config/pon 新增 omci.auth_mode (loid|password), password-only 线路要设 password ==="

exit 0
