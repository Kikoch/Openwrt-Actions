#!/bin/bash
# DIY 后置脚本: 完全按 PonWrt 官方 CI 的方式组装配置
#   1) kconfig.pl 合并 configs/an7581.config + configs/release.config (官方方法)
#   2) 追加只编 Nokia XG-040G-MD (UBI) 的设备选择 (纯追加, 不做 sed 手术)
#   3) 追加自定义附加包 (ponwrt-extra.config)
#   4) make defconfig 展开

set -e

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

# 早失败: MULTI_PROFILE 若还开着, 后面会白编两个多小时, 而且编译步骤
# 写 $GITHUB_ENV 时会因为多行直接被打失败。这里几十秒内就拦住。
if grep -q '^CONFIG_TARGET_MULTI_PROFILE=y' .config; then
  echo "FATAL: CONFIG_TARGET_MULTI_PROFILE 仍为 y, 会编译全部设备"
  echo "       (产物混杂 + 编译步骤 DEVICE_NAME 多行导致 runner 报 Invalid format)"
  grep '^CONFIG_TARGET.*DEVICE.*=y' .config | head -20 || true
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
  exit 1
fi
echo "=== 关键驱动校验通过 ==="

# 提醒: /etc/config/pon 的 schema 随 pon_userspace 演进 (huawei_compat 已改名
# disable_enhanced_security, 新增 registration_id/loid_password)。刷机后不要
# 恢复旧固件的 /etc/config/pon, 否则密码(PLOAM Registration-ID)字段缺失,
# PON 无法注册。
echo "=== 提醒: 不要恢复旧固件的 /etc/config/pon (schema 已变更) ==="
