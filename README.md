# Openwrt-Actions

> **About（仓库简介，填到 GitHub → About → Description）**
> Cloud-build OpenWrt / ImmortalWrt / PonWrt firmware with GitHub Actions: pinned source + pinned feeds, artifact-level verification before release. Targets Nokia XG-040G-MD (Airoha AN7581 XG-PON) and Cudy TR3000 (MT7981).

基于 GitHub Actions 云编译固件（模板来自 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)）。
同一仓库维护两条独立的编译线，共用一套**产物层校验**脚本。

设计原则：**源码定版、feeds 定版、产物先校验后发布。** 编译成功不等于固件能用 ——
`.config` 看着对，产物里可能根本没有目标设备的镜像。

## 两条编译线

| # | Workflow | 设备 / SoC | 源码 | 状态 |
|---|----------|-----------|------|------|
| 1 | `build-ponwrt-xg040g.yml` | Nokia XG-040G-MD (UBI) / Airoha AN7581 | [pbs05/ponwrt](https://github.com/pbs05/ponwrt) pin `5651948f` | 主力，保留 XG-PON 光口 |
| 2 | `build-immortalwrt-cudy-tr3000.yml` | Cudy TR3000 / MT7981B | ImmortalWrt 稳定分支（自动探测 + 增量编译） | 日常使用，含 QModem 套件 |

> 原「Build ImmortalWrt XG-040G-MD（实验）」线已删除：上游 master 滚动快，
> ponwrt DTS / 内核补丁覆盖需要持续 rebase，维护成本高于收益。

## ONU 线（2026-10-09 新增，与第 1 条并行，互不干扰）

| # | Workflow | 设备 / SoC | 源码 | 状态 |
|---|----------|-----------|------|------|
| 3 | `build-onu-xg040g.yml` | Nokia XG-040G-MD (UBI) / Airoha AN7581 | [naoki66/ImmortalWrt-for-Gemtek-brightspeed](https://github.com/naoki66/ImmortalWrt-for-Gemtek-brightspeed) pin `8243d9a5` | **新线**，拿 naoki66 那套 ONU 用户态栈 |

**为什么单独开一条线而不是改第 1 条**：换源码树（不是换 feed）会让第 1 条的
pin、feeds、配置基线全部作废，等于把一条已跑通的线推倒重来。现在两条线并存：

| | 第 1 条（ponwrt-*） | 第 3 条（onu-*） |
|---|---|---|
| 源码 | `pbs05/ponwrt` | `naoki66/ImmortalWrt-for-Gemtek-brightspeed` |
| PON 用户态 | `pbs05/openwrt-pon-userspace` | `naoki66/openwrt-pon-userspace`（= 用户给的 `OpenWrt_ONU_CONFIG`，两仓库内容 diff 为空、HEAD 同为 `77a2c09a`） |
| LuCI 页面 | `luci-app-pon` + `luci-app-iptv` | **`luci-app-onu`**（顶级 ONU 菜单，七页：状态/硬件身份/认证/上网/IPTV/语音/诊断） |
| 配置合并 | `kconfig.pl` + `configs/an7581.config` + `configs/release.config` | `cp 2010.config .config` + `set-build-version.sh`（该 fork 的官方做法） |
| dispatch type | `build-ponwrt` | **`build-onu`** |
| 缓存 key | `ponwrt-dl-` / `ponwrt-ccache-` | **`onu-dl-` / `onu-ccache-`** |
| artifact | `PonWrt_firmware_*` | **`ONU_firmware_*`** |

文件前缀 `onu-*`（`onu-extra.config` / `onu-diy-part1.sh` / `onu-diy-part2.sh` /
`onu-required-packages.txt` / `scripts/verify-onu.sh`），**第 1 条线的文件一个字没动**。

三个值得记的核对结论：

1. **种子配置选 `2010.config` 而不是 `1710.config`** —— `1710.config`（XR1710G）里
   **没有 PON 包**。naoki66 自己那份 XG-040G-MD 固件是拿 1710.config 手工改设备 +
   追加 PON 全家桶编出来的（私有定制，仓库里没有对应 config）。`2010.config` 里
   PON 全家桶全是 `=y`，且 `MULTI_PROFILE` 已经是 not set，改设备即可。
2. **不跑 `scripts/check-gemtek-profile-isolation.sh`** —— 它只认 `gemtek_xr1710g` /
   `gemtek_xg2010g`，else 分支是 `unsupported Gemtek profile` + `exit 1`。改成 nokia
   设备后必然被判死，它是给 Gemtek 做 profile 隔离用的，与本线无关。
3. **firewall4 补丁不会被 `apply-feed-patches.sh` 应用** —— 那个脚本只处理源码树的
   `patches/feeds/<feed>/`（用 `git -C feeds/<feed> apply`），而 firewall4 是源码树内的
   包。所以由 `onu-diy-part1.sh` 塞进 `package/.../firewall4/patches/` 走 quilt。
   本 fork 的 firewall4 是同一个提交 `b6e51575`，那份 rebase 补丁实测可直接复用。

本线额外带上第 1 条线没有的两个修复：**lan1(2.5G) EN8811H 复位时序**
（本 fork 实测仍是 `1s/100ms`，未合入上游修复 → 改成 `10ms/20ms`）与
**firewall4 zone.device flowtable**（PPPoE 底下那层进 flowtable，硬件卸载才生效）。
> 需要恢复可 `git revert` 删除提交。

### 1. Build PonWrt XG-040G-MD

- **产物**: `ponwrt-airoha-an7581-nokia_xg-040g-md-ubi-*-sysupgrade.itb`（+ `-initramfs-recovery.itb`）
- **内置**: 中文 LuCI（**仅 bootstrap 主题**，argon/footstrap/material/openwrt/openwrt-2020 全部移除）、OpenClash、**IPTV（luci-app-iptv + `luci-i18n-iptv-zh-cn`，依赖 `kmod-nft-bridge`）**、DDNS（luci-app-ddns + ddns-scripts-dnspod，含 `luci-i18n-ddns-zh-cn`）、attendedsysupgrade、package-manager、WireGuard（luci-proto-wireguard + wireguard-tools + kmod-wireguard/udptunnel4/6）、BBR、nft-fullcone、zram-swap、USB3 存储
- **2026-10-08 包组成调整（基于上游 master `04986da1e` 的编译结构）**:
  - **补 IPTV**: `luci-app-iptv` + `luci-i18n-iptv-zh-cn`。包在 `pbs05/openwrt-pon-userspace` 的 `luci-app-iptv/`（feeds pin `cce9d756`，已按 ref 直取核对 Makefile / `po/zh_Hans/iptv.po` / `root/etc/config/iptv` 齐全）。`LUCI_DEPENDS:=+luci-base +firewall4 +kmod-nft-bridge` —— 三条基线全开（`firewall4` an7581.config:2767、`kmod-nft-bridge` release.config:3），不用额外补依赖。**`/etc/config/iptv` 出厂 `enabled='0'`** 是"应用默认不接管网络"的设计：要在 LuCI「网络 → IPTV」里勾"启用"、选 LAN 口与服务 VLAN，它才会用 `iptv-apply` 建 8021q VLAN + `br-iptv` 并把该口移出 `br-lan`（nft bridge 族过滤表）。2026-10-06 曾以"`enabled='0'` 白编"为由砍掉，10-08 按需求恢复
  - **删 adblock 全家**: `luci-app-adblock-fast` / `adblock-fast` / `luci-i18n-adblock-fast-zh-cn`，外加 2026-10-03 为它加的四个"推荐组件" `gawk` / `grep` / `sed` / `coreutils-sort`。判据：这七个符号在基线 `configs/an7581.config` 里全是 `is not set`，唯一打开它们的是本仓 `extra.config`；其中 awk/grep/sed/sort 在 `adblock-fast/Makefile` 里是 `+!BUSYBOX_DEFAULT_AWK:gawk` 形式的**条件**依赖，busybox 自带时本来就不拉。撤回 `=y` 后无人 select → 关得掉。**`coreutils-nohup` 保留**（它不是 adblock 依赖，是 18.1 对齐项）
  - 三道闭环同步：`ponwrt-extra.config` 反向覆盖 → `ponwrt-diy-part2.sh` 配置层（require 表进 iptv、FORBID 表进 adblock 7 条）→ workflow `FORBID_PKGS` 产物层。⚠️ **同一符号不许同时出现在 require 与 forbid 两张表里**，否则构建必然判死
- **2026-10-08 需求项核对（组件 / 中文翻译 / 内核）**: 逐条核实后只有一处真缺 —— `luci-i18n-ddns-zh-cn`（已补）。其余三处是上游现状，不是遗漏：
  - `luci-app-openclash`：**上游没有 `luci-i18n-openclash-zh-cn` 这个包**。其 Makefile 不走 luci.mk 的 i18n 机制，而是在 `Build/Prepare` 里用 `po2lmo` 把 `po/zh-cn/openclash.zh-cn.po` 编进包体。中文天然自带。
  - `luci-proto-wireguard`：该 feed 里**没有 `po/` 目录**，luci.mk 只对存在 `po/<lang>/` 的包生成 i18n 包 → 不存在 `luci-i18n-wireguard-zh-cn`。该页面为英文，属上游现状。
  - `zram-swap` + `kmod-zram`：**没有 LuCI 应用**（无 luci-app-zram），走 `/etc/config/zram` + `/etc/init.d/zram-swap`，无界面也就无翻译包。
  - 三道校验闭环：`ponwrt-extra.config` 反向覆盖 → `ponwrt-diy-part2.sh` 配置层断言（新增"除 bootstrap 外主题一律不许 =y/=m"+"14 个需求包全部 =y"）→ workflow `FORBID_PKGS` 产物层反向校验（5 个主题出现在 manifest 即判失败）。
- **OpenClash 和 luci feed 的 pin 必须成对看**: OpenClash 用的是 `immortalwrt/luci` 自带的 `applications/luci-app-openclash`（0.47.156，与上游 vernesong/OpenClash 的 tag 同版）。但 **2026-09 那段时间 immortalwrt/luci 的 master 线把这批第三方 LuCI 应用整段拆走了，2026-10-02 的 `Merge Official Source`(ed0441b1) 才合回**（applications 从 103 → 167 项）；pin 在 `f4f91aee`(9/23) 时 ap 里根本没有 openclash —— 只在 `ponwrt-extra.config` 写 `=y` 的话，`make defconfig` 会当未知符号静默删掉，编译成功、固件里一个字节都没有（run #16 教训）。所以 luci pin 固定在 `ed0441b1`，这是本线唯一一个故意晚于源码 pin 日期的 feed
- **zram 保留说明**: 18.1 那台是 1G 版用不上，但内存更小的同型号设备需要 zram 做 OOM 兜底；内核一变外部 apk 源就没有配套 `kmod-zram`，只能编进固件，所以默认带上（不需要时注释 `ponwrt-extra.config` 里那 5 行，并同步注释 `ponwrt-required-packages.txt` 里的 2 行，否则产物校验会失败）
- **2026-10-03 对齐 18.1 路由器**: 新增 luci-app-iptv（在 `pbs05/openwrt-pon-userspace` 里，早期误判为不可复刻）、ruby + ruby-yaml（OpenClash 依赖）、shellsync + kmod-macvlan、luci-mod-admin-full、luci-lib-uqr、autocore、coreutils-nohup、yq、kmod-mppe；移除 qrencode、luci-app-upnp、kmod-usb-xhci-mtk
- **UPnP 的移除要注意 kconfig 顺序**: 官方 `configs/release.config` 自带 `CONFIG_PACKAGE_luci-app-upnp=y`，base 在前、`ponwrt-extra.config` 在后，同名符号取最后一条 —— 所以必须在 extra.config 里显式写 `# CONFIG_PACKAGE_luci-app-upnp is not set` 反向覆盖，光把上行删掉无效（run #16 产物里 upnp 三件套照样在）。`verify-firmware.sh` 另有一道 `FORBID_PKGS` 产物层反向校验
- **`shellsync` / `kmod-mppe` / `kmod-macvlan` 关不掉（2026-10-06 实测纠正）**: 它们是 `ppp` 的硬依赖 —— `Package/ppp` 的 `DEPENDS:=… +shellsync +kmod-mppe`，`Package/shellsync` 的 `DEPENDS:=+libpthread +kmod-macvlan`；而 `ppp` 在 `include/target.mk` 的 `DEFAULT_PACKAGES.router` 里。整条链路会被转成 `select PACKAGE_xxx`（`target-metadata.pl` 的 `select DEFAULT_ppp` → `package-metadata.pl` 的 `default y if DEFAULT_ppp` → `mconf_depends()` 的 `+foo → select PACKAGE_foo`），而 **`select` 优先于用户写的 `# … is not set`** —— 写多少遍都会被顶回 `=y`（配置阶段断言会判死，实测 run #25/#26）。所以 `ponwrt-extra.config` 让它们保持 `=y`，`FORBID_PKGS` / `FORBID_PKG_LIST` 里**也不能**出现它们，否则产物层校验必然失败。真正砍得掉的是 `adblock-fast` 全家（含 `gawk`/`grep`/`sed`/`coreutils-sort`）与 `kmod-ovpn-backports`
- **`i2c-tools` 与 `libi2c` 必须一起关（2026-10-06）**: 基线是 `CONFIG_PACKAGE_i2c-tools=y` + `CONFIG_PACKAGE_libi2c=m`，而 **`=m` 照样编译**（只是不进镜像），且 `i2c-tools` 的 `DEPENDS:=+libi2c` 会把 `libi2c` 的 `m` 顶成 `y`。只关 `i2c-tools` 的话 `libi2c` 退回 `=m` 继续编，**等于没省**。两个都写 `# … is not set` 才真的不编（已核实上游 select 源 `luci-app-oled` / `python3-smbus` / `meshtasticd` 全未启用）
- **CI 失败诊断走注解**: GitHub 公开仓库的 job 完整日志要 admin/登录，**唯一匿名可读的通道是 `check-runs/{job_id}/annotations`**。所以 `ponwrt-diy-part2.sh` 里每条断言都发 `::error::`（换行编码 `%0A`、`%` 先转义 `%25`），失败时排障不用翻日志。注意 `push.paths` 白名单**不含 `.github/workflows/*` 自身**，只改 workflow 不会触发构建
- **排除**: luci-app-ttyd
- **PON 全栈**: `kmod-airoha-en7572` / `kmod-airoha-xpon` / `kmod-airoha-pon-frontend` / `airoha-ponctl` / `airoha-pond` / `luci-app-pon`
- **已验证**: XG-PON 光口、2.5G LAN（EN8811H）、PPPoE、低内存更新方案（`openclash_lowmem_update.sh`，每日 03:00 停服更新）
- **手动参数**: `source_ref`（换源码版本）、`pin_feeds`（关闭 feeds 定版）、`skip_verify`（排障用）、`release`

### 2. Build ImmortalWrt Cudy TR3000

- 每日 05:30（北京）探测最新 `openwrt-YY.MM` 稳定分支，与 `cudy-tr3000.last-built-ref` 比对，**有新提交才编译**，成功后自动回写
- 一次构建只出一个 profile，手动 Run 时可选：
  - `cudy_tr3000-v1` 原厂分区布局（默认）
  - `cudy_tr3000-256mb-v1` 256MB 内存版
  - `cudy_tr3000-v1-ubootmod` 已刷 OpenWrt U-Boot
- **内置**: 中文 LuCI、OpenClash、zram-swap、adblock-fast 及依赖、QModem 套件（[FUjr/QModem](https://github.com/FUjr/QModem)，src-link 作 feed）、WireGuard
- **已移除**: DDNS（luci-app-ddns / ddns-scripts*，2026-10-03）
- **额外产物**: QModem 独立 apk（`QModem_apk_*` artifact，随 Release 发布），可在其它机器上 `apk add` 安装，不必重刷固件

## 产物层校验（本仓库的关键机制）

`scripts/verify-firmware.sh` 在编译后、上传前执行。校验不过 → 不上传 artifact、不发 Release。
两条线各自通过专属入口调用它：`scripts/verify-ponwrt.sh` / `scripts/verify-tr3000.sh`。

> **为什么要有两个入口**：GitHub 的 `on.push.paths` 是 **OR 语义**，commit 里命中任意一个
> 文件就触发。共用实现一旦直接写进两条线的 paths，改一次校验脚本就会把两条线同时拉起来
> （实测 `63e80ff`、`dba09d9` 两次都是同秒双起，TR3000 单次 3.5 小时白跑）。
> 现在 `verify-firmware.sh` 不进任何 paths，只由两个入口文件转发调用。

| 校验项 | 挡住的问题 |
|--------|-----------|
| 产物目录有可刷写镜像 | 编译静默失败 |
| `profiles.json` 含期望 profile | 目标写错 |
| **有文件名含期望 profile 的镜像** | `make defconfig` 把多个 `DEVICE_*=y` 收敛成最后一个，产物里根本没有目标设备 |
| `supported_devices` 含期望板名 | 刷机时 `sysupgrade` 拒绝镜像 |
| `*.manifest` 含全部关键包 | per-device packages 被清空导致驱动静默落选（PON/2.5G 全灭） |
| 禁止的 profile 未混入产物 | 多 profile 配置互相污染 |

为什么必须做：**`.config` 检查挡不住 `defconfig` 收敛。** 曾出现过同时写三个
`CONFIG_TARGET_mediatek_filogic_DEVICE_*=y`，`.config` 看着正常，产物却只有
`-ubootmod` 镜像，原厂分区机器刷机报 `Device cudy,tr3000-v1 not supported by this image`。

同时归档进产物目录：

- `build.config` — `make defconfig` 后实际生效的完整配置
- `SHA256SUMS` — 所有可刷写镜像的校验和
- `build-info.txt` — 源码 commit、各 feed commit、编译时间、镜像清单

关键包清单按编译线分开维护：`ponwrt-required-packages.txt`、
`cudy-tr3000-required-packages.txt`。只放"缺了就废"的包，别塞可选包，
否则校验会变成噪音。

## 编译配置：哪些包关不掉（踩过的坑）

`ponwrt-extra.config` 里写 `# CONFIG_PACKAGE_x is not set` **只对"没人 select 的符号"有效**。
`DEPENDS:=+foo` 会被 `scripts/package-metadata.pl` 的 `mconf_depends()` 转成
`select PACKAGE_foo`，而 **select 优先级高于用户写的 `is not set`** —— 写多少遍都会被顶回来。

已确认**关不掉**的（别再试着关，也别放进 `FORBID_PKGS`，否则配置阶段必然判死）：

| 包 | 为什么关不掉 |
|----|-------------|
| `shellsync` / `kmod-macvlan` / `kmod-mppe` | `ppp` 的硬依赖（`ppp/Makefile:56`、`shellsync/Makefile:12`），而 `ppp` 在 `include/target.mk` 的 `DEFAULT_PACKAGES.router` 里 → 经 `target-metadata.pl:262` 的 `select DEFAULT_ppp` 顶成 `=y` |
| `kmod-i2c-core` | 一度判「关不掉」：`hwmon.mk:12` 的 `hwmon-core DEPENDS:=+kmod-i2c-core`，而 `hwmon-core` 被三路 select —— `mt76/Makefile:238`（mt7915e）、`netdevices.mk:566`（phy-realtek）、`netdevices.mk:297`（phy-maxlinear），三者基线都是 `=m`。**但本设备没有 WiFi、外接 PHY 只有 en8811（DTS 证实），把三个上游关掉后它就关得掉了**（见下） |

核实方法（别靠推理）：在源码树里 grep `DEPENDS.*<pkg>`，再逐个确认这些上游包
在 `configs/an7581.config` 里是不是 `=y`/`=m`。稀疏克隆只要 36 MB，比反复猜快得多。

### 顺序很重要：先关上游，再关下游

`select` 是单向的 —— 上游还在，下游写 `is not set` 一律无效。本仓库的实际例子：

```text
kmod-mt7915e ─┐
kmod-phy-realtek ─┼─ select ─→ kmod-hwmon-core ─ select ─→ kmod-i2c-core
kmod-phy-maxlinear ─┘
```

所以 `ponwrt-extra.config` 里的顺序是 **WiFi 全家桶 → 冗余 PHY → hwmon-core → i2c-core**，
反过来写等于白写。

**`seed` 里有 ≠ 设备需要。** XG-040G-MD 没有 WiFi（DTS 无 `pcie`/`wlan`/`wifi` 节点，
不 include `an7581-npu-wlan.dtsi`），但官方 `an7581.config` 要兼顾 q1000k / evb /
zn504xg-d 等带 WiFi 的同 SoC 板子，于是整套 `mt76` + `mac80211` + `wpad-openssl`
都是 `=m` 跟着编。同理 `kmod-phy-realtek` / `kmod-phy-maxlinear` / `rtl826x-firmware`
—— 本设备外接 PHY 只有 `en8811`（`ethernet-phy-id03a2.a411`），其余口是 SoC 内置
`gsw_phy2/3/4`（`phy-mode = "internal"`）。**判断"要不要"看设备 DTS 和
`DEVICE_PACKAGES`，不看 seed。**

另注意：**`=m` 不等于不编** —— `m` 照样编译，只是不进镜像。所以 `i2c-tools` 和
`libi2c` 必须一起关（只关前者，`libi2c` 会退回 `=m` 继续编）。

## 可复现性

- **源码定版**: 每条线的 workflow `env.REPO_REF` 固定 commit，手动可覆盖
- **feeds 定版**: `ponwrt-feeds.conf` 用 `src-git <name> <url>^<commit>` 语法把 7 个 feed
  固定到与源码同期的提交。feeds 跟上游 HEAD 走时，依赖超前不会报错，只会让旧配置里的
  符号被静默丢弃 —— 编译照样成功，固件却少了功能
- **dl/ 缓存**: 按 feeds + 配置哈希缓存 `dl/`，重复构建省掉数 GB 重复下载
- **旧记录清理**: 自动删除 7 天前 / 超出 3 条的 workflow runs，Release 只保留最近 3 个

升级源码版本时，**必须同步更新 `ponwrt-feeds.conf` 里的 feeds 提交**。

## 仓库结构

```
├── .github/workflows/
│   ├── build-ponwrt-xg040g.yml            # 线 1: PonWrt XG-040G-MD
│   └── build-immortalwrt-cudy-tr3000.yml  # 线 2: Cudy TR3000 (自动增量)
├── scripts/
│   ├── verify-firmware.sh                 # 产物层校验 + 归档 (共用实现, 不进任何 paths)
│   ├── verify-ponwrt.sh                   # 线 1 入口 (进 build-ponwrt paths)
│   └── verify-tr3000.sh                   # 线 2 入口 (进 build-tr3000 paths)
├── ponwrt-extra.config / -diy-part1.sh / -diy-part2.sh
├── ponwrt-feeds.conf                      # feeds 定版
├── ponwrt-required-packages.txt           # 关键包清单 (校验用)
├── cudy-tr3000-extra.config / -diy-part2.sh
├── cudy-tr3000-required-packages.txt
└── cudy-tr3000.last-built-ref             # 已编译的上游版本 (自动回写)
```

## 分支

| 分支 | 内容 | 体积 |
|---|---|---|
| `main` | 云编译配置、workflow、产物校验脚本（就是这里） | 几十 KB |
| [`flash-guides`](https://github.com/Kikoch/Openwrt-Actions/tree/flash-guides) | 刷机 / 救砖手册（3 个 md） | 极小 |
| [`xg-backup`](https://github.com/Kikoch/Openwrt-Actions/tree/xg-backup) | Nokia XG 系列原厂分区备份（mtd0-16，含 `bosa`/`ri`） | 643 MB |

两个内容分支都是**孤立分支**（无父提交、与 main 无历史关联），
单独 clone / 下载不会把 643 MB 的二进制一起拉下来。

## 使用方法

1. 改对应的 `.config` 并 push 到 main → 自动触发（或在 Actions 页手动 Run workflow）
2. 编译约 1.5~2.5 小时（命中 `dl/` 缓存会更快）
3. 产物校验通过后，在 run 页底部 **Artifacts** 下载固件目录
4. 手动触发时填 `release: yes` 同时发布 Release

## 刷机指南

刷机 / 救砖手册在 **[`flash-guides` 分支](https://github.com/Kikoch/Openwrt-Actions/tree/flash-guides)**：

- [Nokia XG-040G-MD (UBI)](https://github.com/Kikoch/Openwrt-Actions/blob/flash-guides/flash-guides/xg-040g-md.md) — 网页 U-Boot 救砖、首次迁移串口步骤、`bosa`/`ri` 备份警示（参考 [Loong1996 恢复指南](https://loong1996.github.io/ImmortalWrt-Airoha/recovery-guide.html)）
- [Cudy TR3000](https://github.com/Kikoch/Openwrt-Actions/blob/flash-guides/flash-guides/cudy-tr3000.md) — 三种 profile 与设备状态对应表、原厂→OpenWrt 迁移、救砖

原厂分区备份在 **[`xg-backup` 分支](https://github.com/Kikoch/Openwrt-Actions/tree/xg-backup)**（643 MB，含 XG-040G-MD / 1G 版 / XG-140G-MD 的 mtd0-16）。

**XG-040G-MD**: 刷机前备份 `bosa`、`ri` 两个 UBI 卷（光口校准与身份数据）。
刷机前跑 `sysupgrade -T` 检查，失败不要强制升级。

## 免责声明

PonWrt 是用于研究和开发的开源光猫固件项目。

刷写固件或修改 PON 相关配置存在风险，可能导致设备无法启动、配置或设备数据丢失、
PON 无法注册等问题。操作前请务必备份原厂固件及设备相关数据（`xg-backup` 分支是
本仓库自带的分区备份示例，不是你的设备数据）。

使用者应自行确保操作符合当地法律法规及运营商相关规定。请勿将本项目用于未经授权的
网络接入、冒用或复制他人设备身份，或干扰运营商网络正常运行。

因刷写、配置或使用本项目产生的设备故障、网络服务异常及其他后果，由使用者自行承担。

PON 驱动和 LuCI 页面存在，不代表一定能通过你的运营商 OLT 注册。使用设备自身的
`bosa`/`ri`，并在设备上核对 PON 注册、OMCI/OAM、VLAN 与 PPPoE 状态。

## License

[MIT](LICENSE) © P3TERX（模板）
