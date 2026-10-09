#!/bin/bash
# =====================================================================
# ONU 编译线 (naoki66 fork + luci-app-onu) 的产物校验入口
#
# 为什么要单独一个入口:
#   共用实现在 scripts/verify-firmware.sh, 而它被写进多条 workflow 的
#   push paths。GitHub 的 paths 是 OR 语义 —— 改一次共用脚本会把几条线
#   同时拉起来 (实测过同秒双起, 单次 3.5 小时白跑)。
#   所以共用实现不进任何 paths, 每条线引自己的入口文件,
#   改哪条线的校验入口只触发哪条线。
#
# 本线在通用校验之外多做两条源码层断言:
#   1) EN8811H 复位时序 (lan1 2.5G 冷启动不开链) —— 由 onu-diy-part1.sh 改
#   2) firewall4 的 zone.device flowtable 补丁 —— 由 onu-diy-part1.sh 注入
#
# 参数全部由 workflow 通过环境变量传给 verify-firmware.sh, 见该文件顶部说明。
# =====================================================================

# ---------------------------------------------------------------
# 源码层断言 1: EN8811H 复位时序 (1s/100ms -> 10ms/20ms)
#
# 本 fork @8243d9a5 的 an7581-nokia_xg-040g-md-common.dtsi 实测仍是
# 1s/100ms (没有合入上游那个修复), 所以 onu-diy-part1.sh 会去改它。
# 这里在编译之后再验一次源码, 避免 push 了修复却产出没修复的固件。
#
# 找不到源码文件时只警告不失败: build_dir 布局变动不该把好构建判死。
# ---------------------------------------------------------------
DTS_XG_C=$(find openwrt/build_dir -name an7581-nokia_xg-040g-md-common.dtsi 2>/dev/null | head -1)
BAD_ASSERT='reset-assert-us = <1000000>;'
GOOD_ASSERT='reset-assert-us = <10000>;'
BAD_DEASSERT='reset-deassert-us = <100000>;'
GOOD_DEASSERT='reset-deassert-us = <20000>;'

if [ -n "$DTS_XG_C" ]; then
  echo "=== 源码层校验: $DTS_XG_C ==="
  if grep -qF "$BAD_ASSERT" "$DTS_XG_C" || grep -qF "$BAD_DEASSERT" "$DTS_XG_C"; then
    echo "::error::EN8811H 复位时序修复未生效: dts 仍是 1s/100ms (lan1 冷启动会不开链)"
    grep -nE 'reset-(assert|deassert)-us' "$DTS_XG_C" || true
    exit 1
  fi
  if grep -qF "$GOOD_ASSERT" "$DTS_XG_C" && grep -qF "$GOOD_DEASSERT" "$DTS_XG_C"; then
    echo "=== EN8811H 复位时序修复已确认落到内核 dts ==="
    grep -nE 'reset-(assert|deassert)-us' "$DTS_XG_C"
  else
    echo "WARN: EN8811H 复位时序无法确认 (两条特征值都没找到)"
    grep -nE 'reset-(assert|deassert)-us' "$DTS_XG_C" || true
  fi
else
  echo "WARN: 未找到解压后的 an7581-nokia_xg-040g-md-common.dtsi, 跳过该断言"
fi

# ---------------------------------------------------------------
# 源码层断言 2: firewall4 的 zone.device flowtable 补丁
#
# 这个补丁是 luci-app-onu 上网页「PPE flowtable 硬件卸载」的配套项 ——
# 没打上的话 PPPoE 底下那层永远进不了 flowtable, 硬件卸载不生效。
# 它由 onu-diy-part1.sh 拷进 package/network/config/firewall4/patches/,
# 走 quilt 在 firewall4 编译时应用, 所以验的是**解压后的源码**。
# ---------------------------------------------------------------
FW4_UC=$(find openwrt/build_dir -path '*firewall4*' -name fw4.uc 2>/dev/null | head -1)
if [ -n "$FW4_UC" ]; then
  echo "=== 源码层校验: $FW4_UC ==="
  if grep -q 'zone_offload_devices' "$FW4_UC"; then
    echo "=== firewall4 zone.device flowtable 补丁已确认应用 ==="
    grep -n 'zone_offload_devices' "$FW4_UC"
  else
    echo "::error::firewall4 补丁未生效: fw4.uc 里没有 zone_offload_devices"
    echo "--- 检查补丁是否被 quilt 跳过 (patch fuzz / 顺序问题) ---"
    ls -1 openwrt/package/network/config/firewall4/patches/ 2>/dev/null || true
    exit 1
  fi
else
  echo "WARN: 未找到解压后的 fw4.uc, 跳过 firewall4 补丁断言"
fi

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-firmware.sh" "$@"
