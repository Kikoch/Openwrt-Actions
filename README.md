# Openwrt-Actions

基于 GitHub Actions 云编译 OpenWrt / ImmortalWrt 固件（模板来自 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)）。

## 当前维护的编译任务

### 1. Build PonWrt XG-040G-MD（主力/稳定）

- **Workflow**: `.github/workflows/build-ponwrt-xg040g.yml`
- **设备**: Nokia XG-040G-MD (UBI) — Airoha AN7581 XG-PON ONU
- **源码**: [pbs05/ponwrt](https://github.com/pbs05/ponwrt)（ImmortalWrt fork + PON 支持，**保留 XG-PON 光口功能**，pin `5651948f`）
- **内置软件**: 中文 LuCI(仅 bootstrap 主题)、OpenClash、DDNS(含 dnspod)、attendedsysupgrade、package-manager、WireGuard、BBR、nft-fullcone、zram-swap(256MB)、USB3 存储、adblock-fast 及其推荐组件(gawk/grep/sed/coreutils-sort)等
- **明确排除**: luci-app-ttyd（终端）、luci-app-iptv
- **配置文件**: `ponwrt-extra.config`（附加包）+ `ponwrt-diy-part1/2.sh`（基础配置合并，仅编 nokia_xg-040g-md-ubi，含关键驱动强校验）
- **产物**: `ponwrt-airoha-an7581-nokia_xg-040g-md-ubi-*-sysupgrade.itb`
- **已验证**: PON(XG-PON + EN7572 光前端)、2.5G LAN(EN8811H)、PPPoE、zram、低内存更新方案（配套脚本见 `/root/openclash_lowmem_update.sh`，每日 03:00 停服更新，04:00 adblock 列表刷新）

### 2. Build ImmortalWrt XG-040G-MD（实验性）

- **Workflow**: `.github/workflows/build-immortalwrt-xg040g.yml`
- **设备**: 同上 Nokia XG-040G-MD (UBI)
- **源码**: [ImmortalWrt master](https://github.com/ImmortalWrt/ImmortalWrt)（官方已收录本设备，pin `bf156b68`）
- **与 PonWrt 构建的区别**:
  - 上游设备定义含 EN8811H 2.5G PHY，但 **DTS 无 PON 节点、设备定义无 PON 包** → `immortalwrt-diy-part1.sh` 从 ponwrt pin 版本覆盖 4 个 DTS 文件（含 `xpon_mac@1fb64000`、EN7572 光前端），`immortalwrt-extra.config` 显式选择 PON 全栈（pon_drivers/pon_userspace feed）
  - `immortalwrt-diy-part2.sh` 含关键包强校验（PON/2.5G/zram/gawk 缺一即构建失败）
- **内置软件**: 与 PonWrt 构建对齐（同排除项），另含 luci-app-pon
- **风险**: 上游 master 滚动较快，ponwrt DTS 覆盖可能与新内核不兼容；**稳定使用请选 PonWrt 构建产物**，本构建用于跟进上游

### 3. Build ImmortalWrt Cudy TR3000

- **Workflow**: `.github/workflows/build-immortalwrt-cudy-tr3000.yml`
- **设备**: Cudy TR3000（MT7981B），同时编译 3 个 profile：`cudy_tr3000-v1`（原厂分区）、`cudy_tr3000-256mb-v1`（256MB 内存版）、`cudy_tr3000-v1-ubootmod`（OpenWrt U-Boot 分区）
- **源码**: [ImmortalWrt](https://github.com/ImmortalWrt/ImmortalWrt) `openwrt-25.12` 稳定分支
- **内置软件**: 中文 LuCI、QModem 模组管理套件（luci-app-qmodem / qmodem / tom_modem / quectel-CM-5G-M / sms_forwarder）、WireGuard、DDNS(含 dnspod)
- **配置文件**: `cudy-tr3000-extra.config` + `cudy-tr3000-diy-part2.sh`
- **QModem 来源**: [FUjr/QModem](https://github.com/FUjr/QModem)（src-link 作为 feed）

## 使用方法

1. 修改对应任务的 `.config` 文件并 push 到 main → **自动触发编译**（也可在 Actions 页面手动 Run workflow）
2. 编译约 1.5~2.5 小时，进度在 Actions 页面查看
3. 完成后在 run 页面底部 **Artifacts** 下载固件目录
4. 手动触发时可填 `release: yes` 同时发布 Release

## 升级注意事项

- **XG-040G-MD**: 刷机前备份 `bosa`、`ri` 两个 UBI 卷（光口校准数据）
- **TR3000**: 原厂分区机器用 `-v1` / `-256mb-v1` 的 factory 或 initramfs 镜像；已刷 OpenWrt U-Boot 的用 `-ubootmod` 的 sysupgrade 镜像

## License

[MIT](LICENSE) © P3TERX（模板）
