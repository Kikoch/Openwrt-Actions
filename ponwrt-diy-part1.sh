#!/bin/bash
# DIY 前置脚本（feeds 更新前执行）
#
# =====================================================================
# 2026-11-03 战略调整：本线不再叠加任何源码补丁，纯上游构建。
#
# 历史教训（为什么砍掉所有本地补丁）：
#   - run #23：本地 999 号 QoS 补丁被上游 925 补丁重新引入同一行而失效，
#     编译 36 分钟后才被源码断言拦下。
#   - run #36：组 ID 碰撞（hardware-support 撞钉死 feeds 的 sane-backends），
#     本质是"钉死旧 feeds + 上游新增包"造成的，靠本地 sed 打补丁治标。
#   - CVE 回移补丁需要随内核版本判断跳过，逻辑本身也在持续维护。
#
# 现行策略：
#   - 源码：pin 到 pbs05/ponwrt master HEAD
#   - feeds：跟随源码自带 feeds.conf.default（不钉版本，等同官方 CI）
#   - 补丁：无。源码树一个字都不改。
#
# 已知代价（明确接受）：
#   - CVE-2026-98432（Linux 6.18.55，IPv4 TCP ireq_opt UAF，CVSS 9.8）
#     未回移。上游 bump 到 6.18.56 后自动消失。刷机前如需缓解，可在设备侧
#     用 nftables 拦截带 IP Options 的入站 SYN。
#   - lan2/lan3 QoS 通道卡 ~500 Mbps 的问题不再本地修正（上游 999 解）。
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

echo "=== ponwrt-diy-part1: 纯上游构建, 未注入任何源码补丁 ==="
exit 0
