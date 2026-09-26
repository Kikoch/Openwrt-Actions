#!/bin/bash
# DIY 脚本：ImmortalWrt 稳定版 + Cudy TR3000 全部三个 profile + QModem 套件

set -e

# 1. 目标设备: Cudy TR3000 (mediatek/filogic, MT7981B)
#    - v1:          原厂分区布局 (256MB? 标准版, 直接从原厂刷)
#    - 256mb-v1:    256MB 内存版 (原厂分区布局)
#    - v1-ubootmod: OpenWrt U-Boot 布局 (已刷过 U-Boot 的机器用)
cat > .config << 'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_cudy_tr3000-v1=y
CONFIG_TARGET_mediatek_filogic_DEVICE_cudy_tr3000-256mb-v1=y
CONFIG_TARGET_mediatek_filogic_DEVICE_cudy_tr3000-v1-ubootmod=y
EOF

# 2. 追加附加包（QModem 套件 + 中文, 见 cudy-tr3000-extra.config）
[ -e $GITHUB_WORKSPACE/$CONFIG_FILE ] && cat $GITHUB_WORKSPACE/$CONFIG_FILE >> .config

# 3. 展开为完整配置
make defconfig

echo "=== 已选设备 ==="
grep '^CONFIG_TARGET.*DEVICE.*=y' .config || true
echo "=== QModem 相关包 ==="
grep -E 'qmodem|tom_modem|quectel|ubus-at-daemon|sms' .config | grep '=y' || true
