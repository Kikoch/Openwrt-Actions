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

# ---------------------------------------------------------------
# LAN 口 QoS 通道修复 (2026-10-06 v7 定案, lan2/lan3 卡 500M)
#
# 症状: lan2 / lan3 上网被卡在 ~500 Mbps, lan4 满速 1000, lan1(2.5G) 满速。
#       到网关速率正常 —— 因为到网关是本机 CPU 发包, 走的是另一条选通道路径。
#
# 根因 (实测定案, 不是推测):
#   airoha_ppe.c 的 FOE 入口按 DSA 端口号选 QDMA QoS 通道:
#       channel = dsa_port >= 0 ? dsa_port : port->id;
#       channel = channel % AIROHA_NUM_QOS_CHANNELS;   /* 4 */
#   => lan2 -> 通道 2, lan3 -> 通道 3, lan4 -> 通道 0, lan1 -> 通道 0, 通道 1 空置。
#
#   AN7581 上通道 0 实测能跑满: E5 实验 (客户端插在 lan1) 1 秒峰值 119,638 pps,
#   同秒 lan1.tx_bytes = 182.38 MB/s = 1459 Mbps, corr(ch0, lan1.tx_bytes)=0.999。
#   而通道 2/3 在单口独占、无任何竞争时也只有 ~500 Mbps
#   (E1: 客户端在 lan3, ch3 1s 峰值 47,628 pps ≈ 571 Mbps, 同秒 ch0 仅 1 pps)。
#   lan4 之所以一直满速, 就是因为它 (4%4=0) 恰好落在通道 0。
#
#   已排除的方向: TRTCM 令牌桶表用读事务整表读完 = 全 0; TXQ close 全开;
#   CHAN_QOS_MODE=0x11111111 全 SP; 用户态/openclash 无关。详见工作区报告
#   《lan2-4-只有一个口跑满-根因分析.md》与 Obsidian《...根因定位》笔记。
#
# 修法: 新增一个编号最大的 999 号补丁, 排在所有补丁之后, 专门重写 else 分支那一行,
#   让 DSA 目标端口统一走通道 0 (唯一实测能跑满的那条)。**上游补丁一个字都不动。**
#
# 注意: 158 是**上游主线补丁**(Lorenzo Bianconi, netdev, acked by Jakub Kicinski,
#   提交说明原话 "This allows HTB shaping to be applied to HW accelerated
#   traffic"), ImmortalWrt 主线 r41341 里同样存在 ->
#   **这不是 PonWrt 独有的差异**, 两条主线一样中招, 所以只能在本地再叠一层修正。
#
# ⚠️ 关键坑 (run #23 实测踩到, 必读):
#   这一行**不只**出现在 158 里。PonWrt 独有的 925 (add PON PPE offload metadata;
#   openwrt/openwrt 与 immortalwrt 同路径都是 404, 本树独有) 把整段改写成 PON if/else,
#   并在 else 分支里**原样把这一行又引入了一次**:
#
#       } else {
#           channel = dsa_port >= 0 ? dsa_port : port->id;   <-- 又回来了
#           channel %= AIROHA_NUM_QOS_CHANNELS;
#       }
#
#   925 排在 158 与 915-02 之后 -> "只 sed 158" 会被 925 整个覆盖掉。
#   run #23 就是这么挂的: 编译过了 36 分钟, 最后被源码层断言拦下, 报
#   "airoha_ppe.c 仍是 dsa_port % 4 的通道映射"。
#   (而且 925 里那条 "-" 行会因为 158 被改而 context 不匹配, 只靠 patch 的模糊匹配
#    侥幸过关 —— 这种"靠侥幸"的改法不能用。)
#
#   999 的 hunk 是按 925 的 "+" 行写出来的 (即 925 应用**之后**的文件状态),
#   已用真 `patch` 本地验证: rc=0、行数不变、旧行消失。
# ---------------------------------------------------------------
# ⚠️ 2026-10-06: 本修复**暂时停用** —— QOS_999_FIX=no (见下方开关)。
#   停用时上游 158 / 915-02 / 925 补丁保持原样 -> lan2/lan3 仍会卡在
#   ~500 Mbps。这是有意为之: 先出一条不含任何本地内核改动的干净基线。
#
#   开关必须与 scripts/verify-ponwrt.sh 里的 QOS_999_CHECK 同开同关:
#     只开这里、没开那边 -> 编译 3.5 小时后被源码层断言判死 (OLD_QOS 必然还在)
#     只开那边、没开这里 -> 断言形同虚设 (永远走不到 NEW_QOS 分支)
# ---------------------------------------------------------------
QOS_999_FIX=no

if [ "$QOS_999_FIX" = "yes" ]; then
  PATCH_DIR=target/linux/airoha/patches-6.18
  if [ ! -d "$PATCH_DIR" ]; then
    echo "FATAL: 找不到 $PATCH_DIR, LAN 口 QoS 通道修复无法应用"
    exit 1
  fi

  # 卫生: 清掉可能残留的备份文件 (OpenWrt 会把整个补丁目录复制进内核树, 别留垃圾)
  rm -f "$PATCH_DIR"/*.bak "$PATCH_DIR"/*.tmpfix 2>/dev/null || true

  OLD_LINE='channel = dsa_port >= 0 ? dsa_port : port->id;'
  P999="$PATCH_DIR/999-airoha-ppe-force-dsa-qos-channel.patch"

  # 改前先数一遍引用它的补丁文件 (预期 3 个: 158 / 915-02 / 925)。
  # 这里只做报告与健全性检查 —— 真正的改动全部落在 999 补丁里, 不碰上游补丁。
  REF_FILES=$(grep -rlF "$OLD_LINE" "$PATCH_DIR" 2>/dev/null | wc -l | tr -d ' ')
  echo "=== '$OLD_LINE' 被 $REF_FILES 个补丁文件引用 (预期 3: 158 / 915-02 / 925) ==="
  if [ "$REF_FILES" -lt 2 ]; then
    echo "FATAL: 引用该表达式的补丁文件少于 2 个, 上游结构可能已变, 拒绝盲改"
    exit 1
  fi

  # 生成 999 号补丁。用 printf 显式写 \t, 避免编辑器把 tab 存成空格。
  {
    printf '%s\n' '--- a/drivers/net/ethernet/airoha/airoha_ppe.c'
    printf '%s\n' '+++ b/drivers/net/ethernet/airoha/airoha_ppe.c'
    printf '%s\n' '@@ -483,7 +483,7 @@ static int airoha_ppe_foe_entry_prepare('
    printf ' \t\t\t\tchannel = FIELD_GET(AIROHA_PON_QDMA_TCONT_MASK,\n'
    printf ' \t\t\t\t\t\t\t\tpon_tag);\n'
    printf ' \t\t\t} else {\n'
    printf -- '-\t\t\t\tchannel = dsa_port >= 0 ? dsa_port : port->id;\n'
    printf -- '+\t\t\t\tchannel = dsa_port >= 0 ? 0 : port->id;\n'
    printf ' \t\t\t\tchannel %%= AIROHA_NUM_QOS_CHANNELS;\n'
    printf ' \t\t\t}\n'
    printf ' \t\t\tpriority = rt_tos2priority(dsfield);\n'
  } > "$P999"

  # 断言 1: 补丁必须是 11 行 (3 行头部 + 8 行 hunk)
  P999_LINES=$(wc -l < "$P999" | tr -d ' ')
  if [ "$P999_LINES" != "11" ]; then
    echo "FATAL: $P999 行数 $P999_LINES != 11"
    cat "$P999"
    exit 1
  fi
  # 断言 2: 那两条 +/- 行各恰好一次
  N_MINUS=$(grep -c '^-.*dsa_port >= 0 ? dsa_port : port->id;' "$P999" 2>/dev/null || true)
  N_PLUS=$(grep -c '^+.*dsa_port >= 0 ? 0 : port->id;' "$P999" 2>/dev/null || true)
  if [ "$N_MINUS" != "1" ] || [ "$N_PLUS" != "1" ]; then
    echo "FATAL: $P999 的 +/- 行数不对 (minus=$N_MINUS plus=$N_PLUS, 期望各 1)"
    cat "$P999"
    exit 1
  fi
  # 断言 3: 缩进必须是真 tab。检查有没有 "- " / "+ " 这种"tab 被存成空格"的行。
  # (不用 grep -P: macOS 的 BSD grep 不支持, 会静默失败。)
  if grep -qE '^[-+] ' "$P999"; then
    echo "FATAL: $P999 里出现 '- ' 或 '+ ' 开头的行 —— tab 被写成了空格, 补丁会应用失败"
    grep -nE '^[-+] ' "$P999"
    exit 1
  fi

  echo "=== 999 号补丁已就位 (排在所有上游补丁之后, 上游补丁未改动) ==="
  cat "$P999"
  echo "=== LAN 口 QoS 通道修复已注入: DSA 目标端口全部走通道 0 ==="
  echo "=== (lan2/lan3 由通道 2/3 改到通道 0; lan1/lan4 本来就是通道 0, 不受影响) ==="
else
  echo "=== [跳过] 999 号补丁未注入 (QOS_999_FIX=no) ==="
  echo "=== 上游 158 / 915-02 / 925 保持原样 —— lan2/lan3 仍会卡 ~500 Mbps (有意为之) ==="
  echo "=== 重开: 本文件 QOS_999_FIX=yes + scripts/verify-ponwrt.sh QOS_999_CHECK=yes ==="
fi

# ---------------------------------------------------------------
# lan1 (2.5G) 冷启动不开链修复 —— EN8811H 复位时序
#
# 现象: 刷 PonWrt 后 lan1(2.5G) 冷启动起不来, 必须 `ip link set lan1 down/up`
#       复位一次才通; 拔插网线救不回来。刷 ImmortalWrt 没这个问题。
#
# 根因 (离线固件解包 + 源码层按 ref 直取, 双证):
#   target/linux/airoha/dts/an7581-nokia_xg-040g-md-common.dtsi
#     en8811: ethernet-phy@f  (compatible = "ethernet-phy-id03a2.a411")
#       PonWrt      @5651948f9d : reset-assert-us = <1000000> (1s)
#                                 reset-deassert-us = <100000> (100ms)   <-- pin 的 ref 里就是这个
#       ImmortalWrt @f44d1535b4 : reset-assert-us = <10000>   (10ms)
#                                 reset-deassert-us = <20000>   (20ms)
#   两个文件都按 ref 直取核对过 (HTTP 200), 同一节点只差这两个值。
#
#   机制: airoha_eth 是 builtin, 内核初始化阶段就把 MAC+PCS bring-up 完了;
#   PHY 复位由 phylib 在 en8811h probe 之后执行, 晚于 MAC 侧。
#   2500BASE-X 是 MAC<->PHY 带内自协商, SoC 侧 PCS 起来时对端还被摁在复位线上
#   -> rxlock 拿不到训练序列 -> 链路"假 Up"(ethtool 全绿, 但 RX 几乎为 0)。
#   down/up 会重跑 MAC+PCS+DMA ring, 所以能救; 拔插只 flap PHY 层, 救不回来。
#
# 修法: 改回主线一致的 10ms/20ms。DTS 是纯文本, 不需要碰补丁机制。
#       只改内容不改行数, 注释也一起改。
#
# 2026-10-07 状态: 上游 master 已自行修复 (69cd3e269, 2026-10-06), 值同为我们
#       要的 10ms/20ms -> 在源码 pin = 04986da1e 时这段是 no-op (幂等判断见下方)。
#       保留本段是为了能随时回退到老 pin (5651948f, 1s/100ms)。
# ---------------------------------------------------------------
DTS_XG=target/linux/airoha/dts/an7581-nokia_xg-040g-md-common.dtsi
if [ ! -f "$DTS_XG" ]; then
  echo "FATAL: 找不到 $DTS_XG, lan1 复位时序修复无法应用"
  exit 1
fi

# ⚠️ 2026-10-07: 先判「上游是不是已经自己修了」。
#   上游 commit 69cd3e269 (2026-10-06, "airoha: restore EN8811H reset timing")
#   已把本设备的 en8811 节点改成 reset-assert-us = <10000> / deassert = <20000>
#   —— 与我们本来要改成的值完全一致, 连那行注释都删了。
#   旧逻辑在这种情况下会在下面的循环里 grep 到 0 次 -> 直接 FATAL,
#   把整个构建在 DIY part1 判死 (新源码 pin 04986da1e 上必然发生)。
#   所以: 新源码走"跳过"分支, 老 pin (5651948f: 1s/100ms) 照旧走替换分支。
GOOD_ASSERT='reset-assert-us = <10000>;'
GOOD_DEASSERT='reset-deassert-us = <20000>;'
if grep -qF "$GOOD_ASSERT" "$DTS_XG" && grep -qF "$GOOD_DEASSERT" "$DTS_XG"; then
  echo "=== [跳过] 上游已内置 EN8811H 复位时序修复 (10ms/20ms, 69cd3e269), 无需本地改动 ==="
else
  echo "=== 上游未修 (老源码): 本地改回主线值 1s/100ms -> 10ms/20ms ==="

for pair in \
  'reset-assert-us = <1000000>;|reset-assert-us = <10000>;' \
  'reset-deassert-us = <100000>;|reset-deassert-us = <20000>;'
do
  O=$(printf '%s' "$pair" | cut -d'|' -f1)
  N=$(printf '%s' "$pair" | cut -d'|' -f2)
  C=$(grep -cF "$O" "$DTS_XG" 2>/dev/null || true)
  if [ "$C" != "1" ]; then
    echo "FATAL: $DTS_XG 中 '$O' 出现 $C 次 (期望恰好 1 次), 拒绝盲改"
    grep -nF "$O" "$DTS_XG" || true
    exit 1
  fi
  # 不用 sed -i.bak: 会在 dts 目录里留下 .bak, 可能被 Makefile 的通配扫进去
  TMP_DTS="$DTS_XG.tmpfix"
  sed "s|$O|$N|" "$DTS_XG" > "$TMP_DTS"
  if [ "$(wc -l < "$DTS_XG")" != "$(wc -l < "$TMP_DTS")" ]; then
    echo "FATAL: $DTS_XG 替换后行数变了, 拒绝写回"
    rm -f "$TMP_DTS"
    exit 1
  fi
  mv "$TMP_DTS" "$DTS_XG"
  if grep -qF "$O" "$DTS_XG"; then
    echo "FATAL: sed 替换失败, 旧值还在: $O"
    exit 1
  fi
done

  # 注释行也一起改 (只有老源码里才有那行注释; 上游修过后它就没了, 所以放在替换分支里)
  sed -i 's|Hold reset for 1 second and wait 100 ms before probing EN8811H\.|Hold reset for 10 ms and wait 20 ms before probing EN8811H.|' "$DTS_XG"
  echo "=== EN8811H 复位时序已改回主线值 (1s/100ms -> 10ms/20ms) ==="
fi

grep -nE "reset-(assert|deassert)-us|Hold reset for" "$DTS_XG"

exit 0
