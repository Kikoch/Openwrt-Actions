#!/bin/bash
# =====================================================================
# 应用 pon_drivers feed 的本地补丁
#
# 执行时机: workflow 的 "Update feeds" + "Install feeds" **之后**,
#   "Load configuration (diy-part2)" 之前。cwd 必须是 openwrt 源码根。
#
# 为什么不能放进 diy-part1:
#   airoha-xpon 驱动不在主源码树里, 而在 pon_drivers feed 里;
#   feeds 源码要等 ./scripts/feeds update -a 才 clone 下来,
#   diy-part1 跑的时候 feeds/pon_drivers 还不存在。
#
# 补丁来源: 上游 pbs05/ponwrt issue #49 (XG-PON MBI RX overrun wedge)
#   https://github.com/pbs05/ponwrt/issues/49
#   机型 XG-040G-MD / ZN504XG-D, 与本线同一台设备。
#
# 失败策略: 应用不成功就 FATAL 退出, **不产出没修复的固件**。
#   上游驱动改动导致 context 漂移时, 这里会拦住并打印详情,
#   而不是静默跳过、让人以为固件含修复。
# =====================================================================

set -u

PATCH_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}/patches"
DRV_FEED="feeds/pon_drivers"
XPON_DIR="$DRV_FEED/airoha-xpon/src"

echo "=== apply-pon-driver-patches: 驱动补丁注入 ==="

if [ ! -d "$XPON_DIR" ]; then
  echo "FATAL: 找不到 $XPON_DIR"
  echo "       可能 feeds 没 update/install, 或 feed 名不叫 pon_drivers"
  ls -1 feeds/ 2>/dev/null || true
  exit 1
fi

# 记录驱动基线, 便于在产物里追溯补丁打在哪个提交上
if git -C "$DRV_FEED" rev-parse HEAD > /dev/null 2>&1; then
  echo "pon_drivers 基线: $(git -C "$DRV_FEED" rev-parse HEAD)"
  echo "PKG_RELEASE: $(grep -m1 'PKG_RELEASE' "$DRV_FEED/airoha-xpon/Makefile" || echo unknown)"
fi

shopt -s nullglob
PATCHES=("$PATCH_ROOT"/airoha-xpon/*.patch)
shopt -u nullglob

if [ ${#PATCHES[@]} -eq 0 ]; then
  echo "FATAL: $PATCH_ROOT/airoha-xpon/ 下没有补丁"
  exit 1
fi

for p in "${PATCHES[@]}"; do
  name="$(basename "$p")"
  echo "--- 预检 $name ---"
  if ! patch -p1 -d "$DRV_FEED" --dry-run --forward --batch < "$p"; then
    echo "FATAL: $name 无法应用 (上游驱动 context 已漂移)"
    echo "       驱动基线: $(git -C "$DRV_FEED" rev-parse HEAD 2>/dev/null || echo unknown)"
    exit 1
  fi
  if ! patch -p1 -d "$DRV_FEED" --forward --batch < "$p"; then
    echo "FATAL: $name 预检通过但实际应用失败"
    exit 1
  fi
  echo "已应用: $name"
done

# ---------------------------------------------------------------
# 源码层断言: 确认补丁真的落到驱动源码, 不是"打了个空补丁还报成功"
# ---------------------------------------------------------------
check() {
  if ! grep -q "$2" "$1"; then
    echo "FATAL: 断言失败, $1 里没有 '$2'"
    exit 1
  fi
  echo "OK: $1 <- $2"
}

check "$XPON_DIR/airoha-xpon-private.h" "AIROHA_XPON_MBI_RESET_THRESHOLD"
check "$XPON_DIR/airoha-xpon-private.h" "mbi_reset_pending"
# xgpon.c 只负责计数与置位, 字符串只在 main.c 的 link_work 里
check "$XPON_DIR/airoha-xpon-xgpon.c"   "mbi_overrun_streak++"
check "$XPON_DIR/airoha-xpon-xgpon.c"   "atomic_set(&xpon->mbi_reset_pending, 1)"
check "$XPON_DIR/airoha-xpon-main.c"    "MBI RX overrun storm"

echo "=== MBI RX 溢出风暴 -> MAC epoch 复位 已注入 ==="
echo "=== (阈值 32 次 / 最小间隔 60s; 死锁 463s+手动 -> 17.6s 全自动) ==="
exit 0
