#!/bin/bash
# DIY 前置脚本（feeds 更新前执行）
# PonWrt 的 feeds.conf.default 已自带 PON 驱动/用户态源，无需额外添加。
# luci-app-openclash 走 immortalwrt/luci 自带的 applications/luci-app-openclash。
#   前提: luci feed 必须 pin 在 ed0441b1 (2026-10-02 "Merge Official Source") 或之后 ——
#   之前的提交里这批第三方 LuCI 应用被整段拆走了 (详见 ponwrt-feeds.conf 注释)。
#   openclash 缺包时在 extra.config 写 =y 毫无用处: defconfig 会静默删符号。
exit 0
