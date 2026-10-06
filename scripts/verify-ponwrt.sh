#!/bin/bash
# =====================================================================
# PonWrt XG-040G-MD 线的产物校验入口
#
# 为什么要单独一个入口:
#   实现本来在 scripts/verify-firmware.sh, 而它被同时写进了两条 workflow 的
#   push paths。GitHub 的 paths 是 OR 语义 —— 只要 commit 里命中任意一个
#   文件就触发 —— 于是"改一次共用校验脚本"会把 PonWrt 和 TR3000 两条线
#   同时拉起来 (实测 63e80ff / dba09d9 两次都是同秒双起), TR3000 单次 3.5 小时
#   白跑, 还会被后续 push 反复 cancel 重开。
#
#   现在共用实现不再进任何 paths, 两条线各自引自己的入口文件,
#   改哪条线的校验入口只触发哪条线。
#
# 参数全部由 workflow 通过环境变量传给 verify-firmware.sh, 见该文件顶部说明。
# =====================================================================

# ---------------------------------------------------------------
# 源码层断言: 确认「LAN 口 QoS 通道修复」真的落到了解压后的内核源码里。
#
# 修复的注入点是 ponwrt-diy-part1.sh (把 158 号补丁里 dsa_port 那行的右值
# 从 dsa_port 改成 0)。它只在"补丁确实被应用"时才有效, 所以这里在编译之后
# 再验一次源码 —— 避免 push 了修复却产出一个没修复的固件。
#
# 找不到源码文件时只警告不失败: build_dir 布局变动不应该把一个好构建判死。
# ---------------------------------------------------------------
# 2026-10-06: 本断言**暂时停用** —— QOS_999_CHECK=no。
#   与 ponwrt-diy-part1.sh 的 QOS_999_FIX 是一对, 必须同开同关:
#   那边停了 999 号补丁、这边没停的话, 编译 3.5 小时后 OLD_QOS 必然还在,
#   断言会 exit 1, 白编一次。
# ---------------------------------------------------------------
QOS_999_CHECK=no

if [ "$QOS_999_CHECK" = "yes" ]; then
  PPE_C=$(find openwrt/build_dir -path '*linux-*' -name airoha_ppe.c 2>/dev/null | head -1)
  OLD_QOS='channel = dsa_port >= 0 ? dsa_port : port->id;'
  NEW_QOS='channel = dsa_port >= 0 ? 0 : port->id;'

  if [ -n "$PPE_C" ]; then
    echo "=== 源码层校验: $PPE_C ==="
    if grep -qF "$OLD_QOS" "$PPE_C"; then
      echo "::error::LAN 口 QoS 通道修复未生效: airoha_ppe.c 仍是 dsa_port % 4 的通道映射"
      echo "--- 残留的旧行 ---"
      grep -nF "$OLD_QOS" "$PPE_C" || true
      echo "--- AIROHA_FOE_CHANNEL 附近上下文 (看是哪个分支: PON if 分支 / else 分支) ---"
      grep -n -B6 -A3 'AIROHA_FOE_CHANNEL' "$PPE_C" || true
      exit 1
    fi
    if grep -qF "$NEW_QOS" "$PPE_C"; then
      echo "=== LAN 口 QoS 通道修复已确认落到内核源码 ==="
      grep -nF "$NEW_QOS" "$PPE_C"
    else
      echo "WARN: 两条特征行都没找到, 通道映射无法确认 (源码可能已被上游重构)"
      grep -n 'AIROHA_FOE_CHANNEL' "$PPE_C" || true
    fi
  else
    echo "WARN: 未找到解压后的 airoha_ppe.c, 跳过源码层校验"
  fi
else
  echo "=== [跳过] LAN 口 QoS 通道修复的源码层断言已停用 (QOS_999_CHECK=no) ==="
  echo "=== 对应 ponwrt-diy-part1.sh 的 QOS_999_FIX=no: 本次产物不含该修复 ==="
fi

# ---------------------------------------------------------------
# 源码层断言 2: 确认 EN8811H 复位时序修复 (lan1 2.5G 冷启动不开链) 也落到位了。
# 同样只在找到文件时断言, 找不到只警告。
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

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-firmware.sh" "$@"
