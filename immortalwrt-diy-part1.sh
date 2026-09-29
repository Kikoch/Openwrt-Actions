#!/bin/bash
# ImmortalWrt DIY 前置脚本: feeds + DTS/内核补丁覆盖 (PON 支持)
#
# 策略 (v2, rebase 版):
#   imm master 的 airoha 补丁系列已 backport 到 v7.x, 远新于 ponwrt 的分叉基线。
#   整套覆盖 ponwrt 补丁或盲目重命名叠加都会上下文冲突 (run #3 失败根因:
#   608 pcs struct / 922 airoha_eth 3 个 hunk 打不上)。
#   因此:
#   - 保留 imm 全部原生补丁
#   - 仅叠加 ponwrt 独有的 PON 相关补丁 (保留 ponwrt 原编号, 字母序恰好
#     保持与 ponwrt 一致的应用顺序)
#   - 其中 608/922 与 imm 基线存在上下文漂移, 改用本仓库
#     imm-pon-overrides/ 内的 rebase 修复版 (在 vanilla 6.18.52 + imm
#     全系列 + 全部 PON 补丁链上实测 100% 应用)
#   - DTS 仍从 ponwrt pin 版本覆盖 (上游无 xpon 节点)
#   - 跳过: 130/140/141/142(mtd, imm 已支持本机 NAND), 202-29/403(an7583),
#     743/748(phy, 与 imm generic 新版冲突), 915-01/916-02/920-16/310-09/
#     310-10/605(imm 已有同名更新版), 310-12(imm 已含等价改动), 980-983(弃用)
set -e

PONWRT_REF=5651948f9d6e9aa48e22338d6abe650019988448
PONWRT_DTS="https://raw.githubusercontent.com/pbs05/ponwrt/${PONWRT_REF}/target/linux/airoha/dts"
PONWRT_PATCH="https://raw.githubusercontent.com/pbs05/ponwrt/${PONWRT_REF}/target/linux/airoha/patches-6.18"
DTS_DIR=target/linux/airoha/dts
PATCH_DIR=target/linux/airoha/patches-6.18
OVERRIDES_DIR="${GITHUB_WORKSPACE}/imm-pon-overrides"

# 1. PON feeds (与 ponwrt 相同来源)
cat >> feeds.conf.default << 'EOF'
src-git pon_drivers https://github.com/pbs05/openwrt-pon-drivers.git
src-git pon_userspace https://github.com/pbs05/openwrt-pon-userspace.git
EOF

# 2. DTS 覆盖: 从 ponwrt pin 版本拉取 (含 xpon_mac@1fb64000 / EN7572 光前端节点)
for f in an7581.dtsi \
         an758x-nokia_xg-040g-common.dtsi \
         an7581-nokia_xg-040g-md-common.dtsi \
         an7581-nokia_xg-040g-md-ubi.dts ; do
  echo "Overriding ${DTS_DIR}/${f} from ponwrt@${PONWRT_REF}"
  curl -fsSL --retry 5 --retry-all-errors "${PONWRT_DTS}/${f}" -o "${DTS_DIR}/${f}"
done

# 校验覆盖是否成功: an7581.dtsi 必须含 xpon_mac 节点
grep -q 'xpon_mac: ethernet@1fb64000' "${DTS_DIR}/an7581.dtsi" || {
  echo "FATAL: an7581.dtsi 覆盖失败, 缺少 xpon_mac 节点"; exit 1
}
grep -q 'airoha,en7572' "${DTS_DIR}/an7581-nokia_xg-040g-md-common.dtsi" || {
  echo "FATAL: Nokia DTS 覆盖失败, 缺少 en7572 光前端节点"; exit 1
}
echo "=== DTS 覆盖完成 ==="

# 3a. 内核补丁: 从 ponwrt 下载独有 PON 补丁 (原名原序)
#     格式: 远端文件名 <TAB> 内容完整性标记 (取自补丁新增行)
while read -r remotename marker; do
  [ -n "$remotename" ] || continue
  dst="${PATCH_DIR}/${remotename}"
  if [ -e "$dst" ]; then
    echo "FATAL: 补丁冲突, 上游已存在 ${remotename}"; exit 1
  fi
  echo "Adding kernel patch ${remotename} (from ponwrt@${PONWRT_REF})"
  curl -fsSL --retry 5 --retry-all-errors "${PONWRT_PATCH}/${remotename}" -o "$dst"
  grep -q "$marker" "$dst" || {
    echo "FATAL: ${remotename} 下载不完整 (缺少标记 ${marker})"; exit 1
  }
done << 'EOF'
170-net-airoha-fix-MIB-stats-collection-to-be-lossless.patch	airoha_update_hw_stats
202-28-pinctrl-airoha-an7581-split-pon-tx-disable-gpio.patch	pon_tx_disable_gpio
310-11-net-airoha-disconnect-PHY-after-QDMA-teardown.patch	phylink_disconnect_phy
923-01-net-airoha-fix-BQL-underflow-in-shared-QDMA-TX-ring.patch	GLOBAL_CFG_TX_DMA_BUSY_MASK
923-02-net-airoha-dma-map-xmit-frags-with-skb-frag-dma-map.patch	AIROHA_DMA_UNMAPPED
925-net-airoha-add-PON-PPE-offload-metadata.patch	AIROHA_PON_QDMA_GEM_MASK
926-net-airoha-npu-bound-mailbox-wait.patch	AIROHA_NPU_MBOX_TIMEOUT_US
927-net-airoha-select-NBQ-for-PPE-egress-on-external-SerDes.patch	AIROHA_FOE_IB2_NBQ
EOF

# 3b. rebase 修复版 608/922 (本仓库维护, 覆盖 ponwrt 原版上下文漂移)
for f in 608-net-pcs-airoha-add-AN7581-PON-line-modes.patch \
         922-net-airoha-add-AN7581-PON-data-and-control-paths.patch ; do
  if [ -e "${PATCH_DIR}/${f}" ]; then
    echo "FATAL: 补丁冲突, 上游已存在 ${f}"; exit 1
  fi
  echo "Adding rebased kernel patch ${f} (from imm-pon-overrides)"
  cp "${OVERRIDES_DIR}/${f}" "${PATCH_DIR}/${f}"
done

# 校验补丁内容完整 (以 PCS XPON 寄存器定义为标记)
grep -q 'AIROHA_PCS_PMA_XPON_SETTING_0' \
  "${PATCH_DIR}/608-net-pcs-airoha-add-AN7581-PON-line-modes.patch" || {
  echo "FATAL: 608 补丁不完整 (缺少 XPON PCS 定义)"; exit 1
}
grep -q 'pon_link_ops' \
  "${PATCH_DIR}/922-net-airoha-add-AN7581-PON-data-and-control-paths.patch" || {
  echo "FATAL: 922 补丁不完整 (缺少 PON link ops)"; exit 1
}
echo "=== 内核 PON 补丁覆盖完成 (10 个) ==="
exit 0
