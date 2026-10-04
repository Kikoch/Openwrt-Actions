#!/bin/bash
# DIY 前置脚本（feeds 更新前执行）
# PonWrt 的 feeds.conf.default 已自带 PON 驱动/用户态源，无需额外添加。
# luci-app-openclash 确实在 immortalwrt/luci 里，但**只存在于部分提交**：
# master 在 2026-09 这段时间把 ~64 个第三方 LuCI 应用整段拿掉了，
# 2026-10-02 的 "Merge Official Source"(ed0441b1) 才合回来。
# 我们 pin 的 f4f91aee(9/23) 正好落在缺包窗口：applications 只有 103 项，
# merge 后是 167 项。与其把 luci pin 推到 merge 之后（等于多引入 64 个包、
# 整个 feed 前进 10 天），不如直接挂上游源 vernesong/OpenClash，
# 版本与 immortalwrt 自带的完全一致（0.47.156）。
exit 0
