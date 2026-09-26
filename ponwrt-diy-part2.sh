#!/bin/bash
# DIY 后置脚本：合并 PonWrt 基础配置 + 自定义附加包，并只保留目标设备

set -e

# 1. 以 PonWrt 官方 AN7581 基础配置为底（已含 PON 全套包和设备定义）
cat $BASE_CONFIG > .config

# 2. 只编译 Nokia XG-040G-MD (UBI)，关掉其余设备，节省编译时间
sed -i -E 's/^(CONFIG_TARGET_.*DEVICE_[a-z0-9._-]+)=y$/# \1 is not set/' .config
cat >> .config << 'EOF'
CONFIG_TARGET_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y
CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y
EOF

# 3. 追加自定义附加包（OpenClash/DDNS/中文等，见 ponwrt-extra.config）
[ -e $GITHUB_WORKSPACE/$CONFIG_FILE ] && cat $GITHUB_WORKSPACE/$CONFIG_FILE >> .config

# 4. 展开为完整配置
make defconfig

echo "=== 已选设备 ==="
grep '^CONFIG_TARGET.*DEVICE.*=y' .config || true
echo "=== PON 相关包 ==="
grep -E 'PON|PONCTL|POND|XPON|ponctl|pond' .config | grep '=y' | head -20 || true
