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
cat >> .config << 'EOF'
CONFIG_TARGET_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y
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
