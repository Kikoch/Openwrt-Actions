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

# 2. 追加设备选择: 只编 Nokia XG-040G-MD (UBI)
#    注意符号形态: scripts/target-metadata.pl 只生成
#      menuconfig TARGET_DEVICE_<target>_<subtarget>_DEVICE_<profile>
#    即 CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi
#    之前写成 CONFIG_TARGET_airoha_an7581_DEVICE_... (少一个 DEVICE_ 前缀)
#    是根本不存在的符号, make defconfig 会静默丢掉 —— 那行一直是死代码,
#    设备其实是被合并进来的官方 configs/an7581.config 选中的。
cat >> .config << 'EOF'
CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y
EOF

# 3. 追加自定义附加包 (OpenClash/DDNS/中文/WireGuard 等)
[ -e "$GITHUB_WORKSPACE/$CONFIG_FILE" ] && cat "$GITHUB_WORKSPACE/$CONFIG_FILE" >> .config

# 4. 展开为完整配置
make defconfig

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
