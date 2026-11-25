# Openwrt-Actions

> **About（仓库简介，填到 GitHub → About → Description）**
> Cloud-build OpenWrt / ImmortalWrt / PonWrt firmware with GitHub Actions: pinned source, artifact-level verification before release. Targets Nokia XG-040G-MD (Airoha AN7581 XG-PON) and Cudy TR3000 (MT7981).

基于 GitHub Actions 云编译固件（模板来自 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)）。
同一仓库维护**两条固件编译线 + 一条独立安装包线**，产物层校验脚本按线隔离。

设计原则：**源码定版、产物先校验后发布。** 编译成功不等于固件能用 —— `.config` 看着对，产物里可能根本没有目标设备的镜像。

## 编译线

| # | Workflow | 设备 / SoC | 源码 | 状态 |
|---|----------|-----------|------|------|
| 1 | `build-ponwrt-xg040g.yml` | Nokia XG-040G-MD (UBI) / Airoha AN7581 | [pbs05/ponwrt](https://github.com/pbs05/ponwrt)，`REPO_REF` 由看门狗跟随 master HEAD 自动抬升（当前 `d9dd3a49f7`） | 主力，保留 XG-PON 光口 |
| 2 | `build-immortalwrt-cudy-tr3000.yml` | Cudy TR3000 / MT7981B | ImmortalWrt 稳定分支（自动探测 + 增量编译） | 日常使用，含 QModem 套件 |
| 3 | `build-zte-mesh-xg040g.yml` | 16.1 / XG-040G-MD（**不刷固件**） | [cnjn/zte-mesh](https://github.com/cnjn/zte-mesh) + 与线 1 同源的 PonWrt | 独立安装包：4 个 zte-mesh apk + kmod-veth + 可选 qemu-arm-static |

> 已删除的实验线：原「Build ImmortalWrt XG-040G-MD」（DTS / 内核补丁需持续 rebase）与
> 「ONU 线」（`naoki66/ImmortalWrt-for-Gemtek-brightspeed` + `luci-app-onu`，2026-10-09 建、
> 2026-11-15 删）。要恢复可 `git revert` 对应删除提交。

### 1. Build PonWrt XG-040G-MD

- **产物**: `ponwrt-airoha-an7581-nokia_xg-040g-md-ubi-*-sysupgrade.itb`（+ `-initramfs-recovery.itb`）
- **内置**: 中文 LuCI（**仅 bootstrap 主题**）、OpenClash、IPTV（`luci-app-iptv` + `luci-i18n-iptv-zh-cn`）、DDNS、attendedsysupgrade、package-manager、WireGuard、BBR、nft-fullcone、zram-swap、USB3 存储
- **PON 全栈**: `kmod-airoha-en7572` / `kmod-airoha-xpon` / `kmod-airoha-pon-frontend` / `airoha-ponctl` / `airoha-pond` / `luci-app-pon`
- **现行构建策略（2026-11-04 起）**: 纯上游基线，只叠加两个上游自己已实测的定点修复，各自可开关：
  - `patches/airoha-xpon/949-*`：MBI RX 溢出风暴触发 MAC epoch 复位（修 PPPoE 掉线后死锁，上游 issue #49）
  - `patches/airoha-kernel/947-01/02`：AN7581 QDMA SRAM 拥塞剖面（修 lan2/lan3 卡 300–500M，上游 PR #64）
  - 手动 dispatch 用 `mbi_fix=no` / `sram_fix=no` 分别关掉。不再自创补丁；CVE-2026-98432 的本地回移补丁已随内核 6.18.60 删除，不要回加。
- **feeds**: 默认跟随源码自带的 `feeds.conf.default`（等同官方 CI）；`pin_feeds=yes` 才用 `ponwrt-feeds.conf` 钉旧提交。钉旧 feeds 撞过上游组 ID，别「pin 不动只重编」造成混血。
- **自动编译**: `auto-build-ponwrt.yml` 每 6 小时比对上游 HEAD，有更新才抬 pin 并触发构建；`force=yes` 可无条件构建一次。
- **手动参数**: `source_ref`、`pin_feeds`、`skip_verify`、`mbi_fix`、`sram_fix`、`release`
- **已验证**: XG-PON 光口、2.5G LAN（EN8811H）、PPPoE、低内存更新方案（`openclash_lowmem_update.sh`，每日 03:00 停服更新）

### 3. Build ZTE Mesh APK for 16.1（独立安装包线）

- **不改固件**：产物是 `zte-mesh-apk-xg040g-*` bundle，scp 到现有 16.1 后跑 `install-on-16.1.sh` 安装。
- **源码**：PonWrt ref 运行时从线 1 的 `REPO_REF` 读取（保证 kmod 与 6.18.60 内核同版），zte-mesh ref 钉在 workflow 里。
- **依赖处理**：16.1 实机缺 `kmod-veth` → 本线现编；`ip-full` / `kmod-sched-core` 已在机上，仍打进 bundle 兜底。
- **AArch32**：原厂 multiapd 是 ARM32，本机 `/proc/sys/abi/default` 缺失 → COMPAT 不可证。上游 apk 不带模拟器，本线把 aarch64 静态 `qemu-arm-static` 作为**可选文件**放进 bundle（init 会自动判定并使用），不塞进任何 apk。
- **隔离**：独立 dispatch type / concurrency group / cache 前缀 / artifact 前缀，`push.paths` 只含本 workflow，改它不会拉起两条 3.5 小时的固件线。
- **触发**：push 本 workflow 自动构建；手动 Run 可覆盖两个 ref 或选 `release: yes` 发 Release。

### 2. Build ImmortalWrt Cudy TR3000

- 每日 05:30（北京）探测最新 `openwrt-YY.MM` 稳定分支，与 `cudy-tr3000.last-built-ref` 比对，**有新提交才编译**，成功后自动回写
- 一次构建只出一个 profile，手动 Run 时可选：
  - `cudy_tr3000-v1` 原厂分区布局（默认）
  - `cudy_tr3000-256mb-v1` 256MB 内存版
  - `cudy_tr3000-v1-ubootmod` 已刷 OpenWrt U-Boot
- **内置**: 中文 LuCI、zram-swap、adblock-fast 及依赖、QModem 套件（[FUjr/QModem](https://github.com/FUjr/QModem)，src-link 作 feed）、WireGuard
- **已移除**: DDNS（luci-app-ddns / ddns-scripts*，2026-10-03）；OpenClash（2026-10-19 起不再编入固件，改走 `openclash_lowmem_update.sh` 独立更新方案，刷机后 `apk add` 单独安装）
- **额外产物**: QModem 独立 apk（`QModem_apk_*` artifact，随 Release 发布），可在其它机器上 `apk add` 安装，不必重刷固件

## 产物层校验（本仓库的关键机制）

`scripts/verify-firmware.sh` 在编译后、上传前执行。校验不过 → 不上传 artifact、不发 Release。
两条线各自通过专属入口调用它：`scripts/verify-ponwrt.sh` / `scripts/verify-tr3000.sh`。

> **为什么要有两个入口**：GitHub 的 `on.push.paths` 是 **OR 语义**，commit 命中任意一个文件就触发。共用实现一旦直接写进两条线的 paths，改一次校验脚本就会把两条线同时拉起来（TR3000 单次 3.5 小时白跑）。现在 `verify-firmware.sh` 不进任何 paths，只由两个入口转发调用。

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
`cudy-tr3000-required-packages.txt`。只放「缺了就废」的包，别塞可选包，
否则校验会变成噪音。

## 可复现性

- **源码定版**: `build-ponwrt-xg040g.yml` 的 `REPO_REF` 固定 commit，手动 `source_ref` 可覆盖；看门狗抬 pin 时会同步提交并触发构建
- **feeds**: 默认不钉版本（跟随上游）；需要复现旧构建时显式 `pin_feeds=yes`，并同步确认 `ponwrt-feeds.conf` 的 7 个 feed 提交与源码同期
- **dl/ 缓存**: 按 feeds + 配置哈希缓存 `dl/`，重复构建省掉数 GB 重复下载
- **旧记录清理**: 自动删除 7 天前 / 超出 3 条的 workflow runs，Release 只保留最近 3 个

## 仓库结构

```
├── .github/workflows/
│   ├── build-ponwrt-xg040g.yml            # 线 1: PonWrt XG-040G-MD
│   ├── auto-build-ponwrt.yml              # 线 1: 上游更新看门狗 (每 6h)
│   ├── build-immortalwrt-cudy-tr3000.yml  # 线 2: Cudy TR3000 (自动增量)
│   ├── build-zte-mesh-xg040g.yml          # 线 3: 16.1 独立安装包 (不刷固件)
│   └── publish-artifacts-to-release.yml   # 手动发布产物到 Release
├── scripts/
│   ├── verify-firmware.sh                 # 产物层校验 + 归档 (共用实现, 不进任何 paths)
│   ├── verify-ponwrt.sh / verify-tr3000.sh  # 各线专属入口
│   └── apply-pon-driver-patches.sh       # feeds install 后注入 949 补丁
├── patches/
│   ├── airoha-kernel/947-01, 947-02       # QDMA SRAM 拥塞剖面
│   └── airoha-xpon/949-*                 # MBI RX 溢出复位
├── ponwrt-extra.config / -diy-part1.sh / -diy-part2.sh
├── ponwrt-feeds.conf / ponwrt-required-packages.txt
├── cudy-tr3000-extra.config / -diy-part2.sh / -required-packages.txt
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
