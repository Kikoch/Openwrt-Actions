#!/bin/bash
# ImmortalWrt DIY 后置脚本: 组装配置 + 强校验
# 上游无 configs/an7581.config, 从零选择目标/设备, 再追加附加包
set -e

# 1. 目标与设备选择 (Nokia XG-040G-MD UBI)
cat >> .config << 'EOF'
CONFIG_TARGET_airoha=y
CONFIG_TARGET_airoha_an7581=y
CONFIG_TARGET_airoha_an7581_DEVICE_nokia_xg-040g-md-ubi=y
CONFIG_TARGET_ROOTFS_TARGZ=y
EOF

# 2. 附加包 (对齐 ponwrt 构建 + 本次新增)
[ -e "$GITHUB_WORKSPACE/immortalwrt-extra.config" ] && cat "$GITHUB_WORKSPACE/immortalwrt-extra.config" >> .config

# 3. 展开为完整配置
make defconfig

echo "=== 已选设备 ==="
grep '^CONFIG_TARGET.*DEVICE.*=y' .config || true

# 4. 强校验: 关键硬件驱动缺失则构建失败
#    (ponwrt 教训: per-device packages 被置空时驱动悄悄落选,
#     产出能开机但 PON/2.5G 全灭的固件)
MISSING=""
for pkg in kmod-airoha-en7572 kmod-phy-airoha-en8811h kmod-airoha-xpon \
           kmod-airoha-pon-frontend airoha-ponctl airoha-pond \
           zram-swap gawk; do
  grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || MISSING="$MISSING $pkg"
done
if [ -n "$MISSING" ]; then
  echo "FATAL: 关键包未进入配置:$MISSING"
  exit 1
fi
echo "=== 关键包校验通过 ==="
