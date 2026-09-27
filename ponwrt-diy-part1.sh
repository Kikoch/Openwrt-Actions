#!/bin/bash
# DIY 前置脚本（feeds 更新前执行）
# PonWrt 的 feeds.conf.default 已自带 PON 驱动/用户态源，无需额外添加。
# luci-app-openclash / luci-app-filebrowser 已包含在 ImmortalWrt luci feed 中。
# 如需加第三方 feed，在此处追加，例如:
# echo 'src-git xxx https://github.com/xxx/xxx' >> feeds.conf.default
exit 0
