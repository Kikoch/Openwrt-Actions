#!/bin/bash
# DIY 脚本：ImmortalWrt 稳定版 + Cudy TR3000 全部三个 profile + QModem 套件

set -e

# 1. 目标设备: Cudy TR3000 (mediatek/filogic, MT7981B)
#    一次构建只能出一个 profile: make defconfig 会把多个 DEVICE_* 收敛成
#    最后一个 (曾导致只产出 ubootmod 镜像, 原厂分区机器刷不了)。
#    用 PROFILE 环境变量指定, 可选值:
#      - cudy_tr3000-v1          原厂分区布局 (设备上报 cudy,tr3000-v1)
#      - cudy_tr3000-256mb-v1    256MB 内存版 (原厂分区布局)
#      - cudy_tr3000-v1-ubootmod 已刷 OpenWrt U-Boot 的机器
PROFILE="${PROFILE:-cudy_tr3000-v1}"
case "$PROFILE" in
  cudy_tr3000-v1|cudy_tr3000-256mb-v1|cudy_tr3000-v1-ubootmod) ;;
  *) echo "FATAL: 未知 PROFILE=$PROFILE"; exit 1 ;;
esac
echo "=== 构建 profile: $PROFILE ==="
cat > .config << EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_${PROFILE}=y
EOF

# 2. 追加附加包（QModem 套件 + 中文, 见 cudy-tr3000-extra.config）
[ -e $GITHUB_WORKSPACE/$CONFIG_FILE ] && cat $GITHUB_WORKSPACE/$CONFIG_FILE >> .config

# 3. 展开为完整配置
make defconfig

echo "=== 已选设备 ==="
grep '^CONFIG_TARGET.*DEVICE.*=y' .config || true
echo "=== QModem 相关包 ==="
grep -E 'qmodem|tom_modem|quectel|ubus-at-daemon|sms' .config | grep '=y' || true

# 4. 强校验: 关键包缺失则构建失败
MISSING=""
for pkg in luci-app-openclash zram-swap kmod-zram luci-app-adblock-fast gawk; do
  grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || MISSING="$MISSING $pkg"
done
if [ -n "$MISSING" ]; then
  echo "FATAL: 关键包未进入配置:$MISSING"
  exit 1
fi
echo "=== 关键包校验通过 ==="
