#!/bin/bash
# DIY 前置脚本（feeds 更新前执行）
# PonWrt 的 feeds.conf.default 已自带 PON 驱动/用户态源，无需额外添加。
# luci-app-openclash 不在任何官方 feed 里, 由 ponwrt-feeds.conf 新增的
# vernesong/OpenClash feed 提供 (run #16 漏包的根因)。
exit 0
