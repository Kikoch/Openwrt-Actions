#!/bin/bash
# ImmortalWrt DIY 前置脚本: feeds + DTS/内核补丁覆盖
# 上游 master 已收录本设备与 EN8811H PHY, 但:
#   1) DTS 无 PON 相关节点 (xpon_mac / EN7572 光前端)
#   2) 内核缺 PON 侧改动 (PCS PON 模式 / airoha_eth PON 数据路径 /
#      PPE offload 元数据 / pinctrl pon 组) -> airoha-xpon 树外模块编译失败
# 必须用 ponwrt pin 版本的 DTS + 内核补丁覆盖, 否则 PON 无法工作。
set -e

PONWRT_REF=5651948f9d6e9aa48e22338d6abe650019988448
PONWRT_DTS="https://raw.githubusercontent.com/pbs05/ponwrt/${PONWRT_REF}/target/linux/airoha/dts"
PONWRT_PATCH="https://raw.githubusercontent.com/pbs05/ponwrt/${PONWRT_REF}/target/linux/airoha/patches-6.18"
DTS_DIR=target/linux/airoha/dts
PATCH_DIR=target/linux/airoha/patches-6.18

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

# 3. 内核补丁覆盖: airoha-xpon 树外模块依赖的 PON 内核侧改动
#    (重命名为 98x 序号, 避免与上游既有补丁编号冲突; 若上游同名则报错)
while read -r newname remotename; do
  [ -n "$newname" ] || continue
  dst="${PATCH_DIR}/${newname}"
  if [ -e "$dst" ]; then
    echo "FATAL: 补丁编号冲突, 上游已存在 ${newname}"; exit 1
  fi
  echo "Adding kernel patch ${newname} (from ponwrt: ${remotename})"
  curl -fsSL --retry 5 --retry-all-errors "${PONWRT_PATCH}/${remotename}" -o "$dst"
done << 'EOF'
980-pinctrl-airoha-an7581-split-pon-tx-disable-gpio.patch 202-28-pinctrl-airoha-an7581-split-pon-tx-disable-gpio.patch
981-net-pcs-airoha-add-AN7581-PON-line-modes.patch 608-net-pcs-airoha-add-AN7581-PON-line-modes.patch
982-net-airoha-add-AN7581-PON-data-and-control-paths.patch 922-net-airoha-add-AN7581-PON-data-and-control-paths.patch
983-net-airoha-add-PON-PPE-offload-metadata.patch 925-net-airoha-add-PON-PPE-offload-metadata.patch
EOF

# 校验补丁内容完整 (以 PCS XPON 寄存器定义为标记)
grep -q 'AIROHA_PCS_PMA_XPON_SETTING_0' \
  "${PATCH_DIR}/981-net-pcs-airoha-add-AN7581-PON-line-modes.patch" || {
  echo "FATAL: 981 补丁下载不完整 (缺少 XPON PCS 定义)"; exit 1
}
echo "=== 内核 PON 补丁覆盖完成 (4 个) ==="
exit 0
