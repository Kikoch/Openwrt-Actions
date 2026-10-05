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

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-firmware.sh" "$@"
