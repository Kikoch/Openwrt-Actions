#!/bin/bash
# =====================================================================
# PonWrt XG-040G-MD 线的产物校验入口
#
# 为什么要单独一个入口:
#   实现本来在 scripts/verify-firmware.sh, 而它被同时写进了两条 workflow 的
#   push paths。GitHub 的 paths 是 OR 语义 —— 只要 commit 里命中任意一个
#   文件就触发 —— 于是"改一次共用校验脚本"会把 PonWrt 和 TR3000 两条线
#   同时拉起来, TR3000 单次 3.5 小时白跑。
#   现在共用实现不再进任何 paths, 两条线各自引自己的入口文件。
#
# 参数全部由 workflow 通过环境变量传给 verify-firmware.sh, 见该文件顶部说明。
#
# 2026-11-03: 本线改为纯上游构建, 不再注入任何源码补丁。
#   - 已删除 LAN QoS 999 补丁的源码层断言 (补丁本身已移除)。
#   - 保留 EN8811H 复位时序断言: 它校验的是**上游自带**的修复 (69cd3e269,
#     10ms/20ms), 若上游回归到 1s/100ms 会在这里拦下 -> 固件不会带着 lan1
#     冷启动不开链的问题出厂。
# =====================================================================

# ---------------------------------------------------------------
# 源码层断言: EN8811H 复位时序必须为主线值 (lan1 2.5G 冷启动不开链)
#
# 上游 69cd3e269 (2026-10-06) 已把本设备 en8811 节点改成
#   reset-assert-us = <10000> / reset-deassert-us = <20000>
# 这里只做回归保护: 出现旧值 (1s/100ms) 判死, 出现新值通过。
# 找不到解压后的 dtsi 时只警告 —— build_dir 布局变动不应把好构建判死。
# ---------------------------------------------------------------
DTS_XG_C=$(find openwrt/build_dir -name an7581-nokia_xg-040g-md-common.dtsi 2>/dev/null | head -1)
BAD_ASSERT='reset-assert-us = <1000000>;'
GOOD_ASSERT='reset-assert-us = <10000>;'
BAD_DEASSERT='reset-deassert-us = <100000>;'
GOOD_DEASSERT='reset-deassert-us = <20000>;'

if [ -n "$DTS_XG_C" ]; then
  echo "=== 源码层校验: $DTS_XG_C ==="
  if grep -qF "$BAD_ASSERT" "$DTS_XG_C" || grep -qF "$BAD_DEASSERT" "$DTS_XG_C"; then
    echo "::error::EN8811H 复位时序是旧的 1s/100ms (上游回归?) —— lan1 冷启动会不开链"
    grep -nE 'reset-(assert|deassert)-us' "$DTS_XG_C" || true
    exit 1
  fi
  if grep -qF "$GOOD_ASSERT" "$DTS_XG_C" && grep -qF "$GOOD_DEASSERT" "$DTS_XG_C"; then
    echo "=== EN8811H 复位时序为主线值 (10ms/20ms) ==="
    grep -nE 'reset-(assert|deassert)-us' "$DTS_XG_C"
  else
    echo "WARN: EN8811H 复位时序无法确认 (两条特征值都没找到)"
    grep -nE 'reset-(assert|deassert)-us' "$DTS_XG_C" || true
  fi
else
  echo "WARN: 未找到解压后的 an7581-nokia_xg-040g-md-common.dtsi, 跳过该断言"
fi

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-firmware.sh" "$@"
