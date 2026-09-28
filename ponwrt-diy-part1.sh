#!/bin/bash
# DIY 前置脚本（feeds 更新前执行）
# PonWrt 的 feeds.conf.default 已自带 PON 驱动/用户态源，无需额外添加。
# luci-app-openclash 已包含在 ImmortalWrt luci feed 中。

# Aurora 主题 (现网路由器使用中, 公开源: eamonxg/luci-theme-aurora)
echo 'src-git aurora https://github.com/eamonxg/luci-theme-aurora' >> feeds.conf.default

exit 0
