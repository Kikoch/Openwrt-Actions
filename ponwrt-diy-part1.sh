#!/bin/bash
# DIY 前置脚本（feeds 更新前执行）
#
# =====================================================================
# 现行策略（2026-11-11 复核）：纯上游基线 + 两个可开关的上游定点修复。
#   - 源码：pin 到 pbs05/ponwrt master HEAD（当前 d9dd3a49f7，内核 6.18.60）
#   - feeds：跟随源码自带 feeds.conf.default（不钉版本，等同官方 CI）
#   - 补丁：仅 947 SRAM 拥塞剖面（本脚本注入）与 949 MBI RX 溢出复位
#     （feeds install 后由 scripts/apply-pon-driver-patches.sh 注入），
#     两者都能通过 workflow_dispatch 关掉。不再叠加任何自创改法。
#
# CVE-2026-98432（Linux 6.18.55，IPv4 TCP ireq_opt UAF，CVSS 9.8）：
#   修复在 6.18.56，本线内核 6.18.60 已含。历史上的
#   patches/kernel/960-CVE-2026-98432-*.patch、CVE_98432_FIX 开关、
#   内核版本判断与源码断言、设备侧 nftables 缓解规则全部已删除；
#   编译链路里不再有任何 CVE 相关脚本、配置或校验。不要回加。
#
# 历史教训（为什么不再自创补丁）：
#   - run #23：本地 999 号 QoS 补丁被上游 925 补丁重新引入同一行而失效，
#     编译 36 分钟后才被源码断言拦下。
#   - run #36：组 ID 碰撞（hardware-support 撞钉死 feeds 的 sane-backends），
#     本质是"钉死旧 feeds + 上游新增包"造成的，靠本地 sed 打补丁治标。
#   - CVE 回移补丁需要随内核版本判断跳过，内核 bump 后成了纯负资产。
#
# 其余已知项：
#   - lan2/lan3 吞吐受 QDMA SRAM 动态阈值影响，由 947 本地修正（PR #64 未合并）。
#   - lan1 2.5G 冷启动：上游 69cd3e269 已自修（10ms/20ms），无需本地改。
#
# PonWrt 的 feeds.conf.default 已自带 PON 驱动/用户态源，无需额外添加。
# luci-app-openclash 走 immortalwrt/luci 自带，当前 HEAD 已含（167 个应用）。
# =====================================================================

# ---------------------------------------------------------------
# 清掉 dl 缓存里被还原出来的 go-mod-cache
#
# 症状：yq（Go 包）三次 make 都失败，报 "no required module provides package ..."，
#   而那些文件在磁盘上确实存在 —— Go 的 module loader 看不到它们。
# 成因：actions/cache 的 restore-key 兜底还原出来的 go-mod-cache 残缺，
#   而构建期 GOPROXY=off，缺东西不会去补，重试必然复现。
# 处理：删掉让它重新下载。这不是补丁，是缓存卫生，不改任何源码。
# ---------------------------------------------------------------
for d in "$PWD/dl/go-mod-cache" /workdir/openwrt/dl/go-mod-cache; do
  if [ -d "$d" ]; then
    echo "删除还原出来的 go-mod-cache: $d (不可信, 见脚本注释)"
    rm -rf "$d"
  fi
done

echo "=== ponwrt-diy-part1: 缓存卫生完成 ==="

# ---------------------------------------------------------------
# 947 SRAM 拥塞剖面 (2026-11-04 引入, 上游 pbs05/ponwrt PR #64)
#
# 症状: XG-040G-MD 的 lan2/lan3 互联网方向吞吐被卡在 ~300-500 Mbps,
#       内网 iperf3 正常, lan1(2.5G)/lan4 正常 (上游 issue #50 同机型报告)。
#
# 根因: AN7581 默认开启 TX 拥塞丢弃, 但从没编程动态阈值 ->
#       遗留的 channel/queue 最小值只有 22/2 ->
#       2.5G 入向突发打向 1G 出口时, 即使平均只有 500 Mbps 也提前丢包。
#       PR #64 按 AN7581 SDK 的 16K SRAM 剖面初始化 total/channel/queue
#       三级阈值 + DEI 半值边界 + 250us 动态重算, 只对
#       airoha_is_7581() 且 QDMA0/QDMA1 且 16384 描述符池生效。
#
# 状态 (2026-11-10 复核): PR #64 仍是 open + draft, 未合并;
#       ponwrt HEAD d9dd3a49 的 patches-6.18/ 里没有 947-*, Linux 主线
#       airoha_regs.h 也没有 REG_TXQ_DYN_*_THR。两个补丁都未被上游吸收。
#       本线 REPO_REF 已于 2026-11-10 抬到 d9dd3a49 (内核 6.18.60),
#       已在 6.18.60 源码上按字母序 git apply 完整 172 个上游补丁 (172/172 通过),
#       再链式应用 947-01 -> 947-02 均成功, 落地断言与编译期依赖符号全部存在。
#       所以只能继续本地叠加。
#       关闭方式: 手动运行 workflow 时设 sram_fix=no。
#
# 两个补丁有依赖: WAN 那个的上下文引用 LAN 那个新加的函数,
# 必须严格按 01 -> 02 顺序应用, 文件名前缀已保证字母序。
# ---------------------------------------------------------------
SRAM_FIX="${WITH_SRAM_FIX:-1}"
if [ "$SRAM_FIX" = "1" ]; then
  PATCH_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")" && pwd)}/patches/airoha-kernel"
  DEST=target/linux/airoha/patches-6.18
  if [ ! -d "$DEST" ]; then
    echo "FATAL: 找不到 $DEST (target/linux/airoha 布局变了?)"
    exit 1
  fi
  for p in 947-01-net-airoha-initialize-lan-sram-congestion.patch \
           947-02-net-airoha-initialize-wan-sram-congestion.patch; do
    if [ ! -f "$PATCH_ROOT/$p" ]; then
      echo "FATAL: 缺少 $PATCH_ROOT/$p"
      exit 1
    fi
    cp "$PATCH_ROOT/$p" "$DEST/$p"
    echo "已安装内核补丁: $DEST/$p"
  done
  echo "=== 947 SRAM 拥塞剖面已注入: AN7581 QDMA0(16K池) 按 SDK 阈值初始化 ==="
else
  echo "=== WITH_SRAM_FIX=0: 跳过 947 SRAM 拥塞剖面 (上游默认行为) ==="
fi

exit 0
