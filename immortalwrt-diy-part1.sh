#!/bin/bash
# ImmortalWrt DIY 前置脚本: feeds + DTS 覆盖
# 上游 DTS (an7581.dtsi / nokia_xg-040g-*) 不含 PON 相关节点,
# 必须用 ponwrt pin 版本的 DTS 覆盖, 否则 airoha-xpon 无法 probe。
set -e

PONWRT_REF=5651948f9d6e9aa48e22338d6abe650019988448
DTS_BASE="https://raw.githubusercontent.com/pbs05/ponwrt/${PONWRT_REF}/target/linux/airoha/dts"
DTS_DIR=target/linux/airoha/dts

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
  curl -fsSL --retry 5 --retry-all-errors "${DTS_BASE}/${f}" -o "${DTS_DIR}/${f}"
done

# 校验覆盖是否成功: an7581.dtsi 必须含 xpon_mac 节点
grep -q 'xpon_mac: ethernet@1fb64000' "${DTS_DIR}/an7581.dtsi" || {
  echo "FATAL: an7581.dtsi 覆盖失败, 缺少 xpon_mac 节点"; exit 1
}
grep -q 'airoha,en7572' "${DTS_DIR}/an7581-nokia_xg-040g-md-common.dtsi" || {
  echo "FATAL: Nokia DTS 覆盖失败, 缺少 en7572 光前端节点"; exit 1
}
echo "=== DTS 覆盖完成 ==="
exit 0
