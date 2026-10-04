#!/bin/bash
# DIY 前置脚本（feeds 更新前执行）
# PonWrt 的 feeds.conf.default 已自带 PON 驱动/用户态源，无需额外添加。
# luci-app-openclash 走 immortalwrt/luci 自带的 applications/luci-app-openclash。
#   前提: luci feed 必须 pin 在 ed0441b1 (2026-10-02 "Merge Official Source") 或之后 ——
#   之前的提交里这批第三方 LuCI 应用被整段拆走了 (详见 ponwrt-feeds.conf 注释)。
#   openclash 缺包时在 extra.config 写 =y 毫无用处: defconfig 会静默删符号。

# ---------------------------------------------------------------
# 清掉 dl 缓存里被还原出来的 go-mod-cache (run #18 学来的教训)
#
# 症状: yq (Go 包) 三次 make (j / j1 / V=s) 都失败, 报一堆长得一模一样的错:
#     no required module provides package github.com/zclconf/go-cty/cty/internal/graphemes
#     no required module provides package github.com/google/go-cmp/cmp/internal/flags
#     no required module provides package github.com/pkg/diff/intern
#     build constraints exclude all Go files in .../go-isatty@v0.0.20
#   而那些文件在磁盘上明明存在 —— 说明 Go 的 module loader 看不到它们。
#
# 成因两条:
#   1) 缓存是由 actions/cache 的 restore-key 兜底还原出来的 (改了 feeds.conf
#      主 key 没命中), 提取出来的 module 目录残缺/缺 cache/download 元数据;
#   2) 构建期 Go 是离线跑的 (GOPROXY=off), 日志里连一条 "go: downloading"
#      都没有, 缺东西不会去补, 直接判失败 —— 所以重试多少次都必然复现。
#
# 处理: 删掉让它重新下载。放在这里 (feeds update / make download 之前) 最合适:
#   下载阶段有网, 补回来就行; 代价只是多花几分钟, 比重做整个 dl 缓存便宜。
# ---------------------------------------------------------------
for d in "$PWD/dl/go-mod-cache" /workdir/openwrt/dl/go-mod-cache; do
  if [ -d "$d" ]; then
    echo "删除还原出来的 go-mod-cache: $d (不可信, 见脚本注释)"
    rm -rf "$d"
  fi
done


exit 0
