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
> 需要恢复可 `git revert` 删除提交。

### 1. Build PonWrt XG-040G-MD

- **产物**: `ponwrt-airoha-an7581-nokia_xg-040g-md-ubi-*-sysupgrade.itb`（+ `-initramfs-recovery.itb`）
- **内置**: 中文 LuCI（bootstrap 主题）、OpenClash、DDNS（含 dnspod）、attendedsysupgrade、package-manager、WireGuard、BBR、nft-fullcone、zram-swap、USB3 存储、adblock-fast 及依赖（gawk/grep/sed/coreutils-sort）
- **OpenClash 和 luci feed 的 pin 必须成对看**: OpenClash 用的是 `immortalwrt/luci` 自带的 `applications/luci-app-openclash`（0.47.156，与上游 vernesong/OpenClash 的 tag 同版）。但 **2026-09 那段时间 immortalwrt/luci 的 master 线把这批第三方 LuCI 应用整段拆走了，2026-10-02 的 `Merge Official Source`(ed0441b1) 才合回**（applications 从 103 → 167 项）；pin 在 `f4f91aee`(9/23) 时 ap 里根本没有 openclash —— 只在 `ponwrt-extra.config` 写 `=y` 的话，`make defconfig` 会当未知符号静默删掉，编译成功、固件里一个字节都没有（run #16 教训）。所以 luci pin 固定在 `ed0441b1`，这是本线唯一一个故意晚于源码 pin 日期的 feed
- **zram 保留说明**: 18.1 那台是 1G 版用不上，但内存更小的同型号设备需要 zram 做 OOM 兜底；内核一变外部 apk 源就没有配套 `kmod-zram`，只能编进固件，所以默认带上（不需要时注释 `ponwrt-extra.config` 里那 5 行，并同步注释 `ponwrt-required-packages.txt` 里的 2 行，否则产物校验会失败）
- **2026-10-03 对齐 18.1 路由器**: 新增 luci-app-iptv（在 `pbs05/openwrt-pon-userspace` 里，早期误判为不可复刻）、ruby + ruby-yaml（OpenClash 依赖）、shellsync + kmod-macvlan、luci-mod-admin-full、luci-lib-uqr、autocore、coreutils-nohup、yq、kmod-mppe；移除 qrencode、luci-app-upnp、kmod-usb-xhci-mtk
- **UPnP 的移除要注意 kconfig 顺序**: 官方 `configs/release.config` 自带 `CONFIG_PACKAGE_luci-app-upnp=y`，base 在前、`ponwrt-extra.config` 在后，同名符号取最后一条 —— 所以必须在 extra.config 里显式写 `# CONFIG_PACKAGE_luci-app-upnp is not set` 反向覆盖，光把上行删掉无效（run #16 产物里 upnp 三件套照样在）。`verify-firmware.sh` 另有一道 `FORBID_PKGS` 产物层反向校验
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
│   └── verify-firmware.sh                 # 产物层校验 + 归档 (两条线共用)
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
