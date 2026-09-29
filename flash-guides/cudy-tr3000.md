# Cudy TR3000 刷机指南

适用本仓库 **Build ImmortalWrt Cudy TR3000** 工作流产物（ImmortalWrt 稳定分支，含 QModem 套件）。

## 0. 三种固件变体对应三种设备状态

| 你的机器当前状态 | 用哪个 profile |
|---|---|
| 原厂固件，未刷过 | `cudy_tr3000-v1`（原厂分区布局）的 **factory 镜像** |
| 原厂固件，256MB 内存版 | `cudy_tr3000-256mb-v1` 的 **factory 镜像** |
| 已刷 OpenWrt U-Boot（v1-ubootmod） | `cudy_tr3000-v1-ubootmod` 的 **sysupgrade 镜像** |

看错分区布局强刷会变砖，不确定就先在 Cudy 官网按 SN/型号确认硬件版本。

### 镜像类型速查（factory / initramfs / sysupgrade）

| 当前状态 | 目标 | 用哪个镜像 |
|---|---|---|
| 原厂固件 | OpenWrt（原厂分区） | `*-factory.bin`（原厂 Web 升级入口） |
| 原厂固件 | OpenWrt（ubootmod） | 先刷 `*-initramfs-*` 进内存系统，再迁移 U-Boot（见 2.3），最后刷 `*-sysupgrade.bin` |
| OpenWrt（原厂分区） | 更新版本 | `*-sysupgrade.bin`（**必须**是 v1/256mb-v1 的） |
| OpenWrt（ubootmod） | 更新版本 | `*-sysupgrade.bin`（**必须**是 ubootmod 的） |

- `factory`：给**原厂固件**的 Web 升级界面刷的；
- `initramfs`：只在内存中启动、不写闪存，用于过渡与救援；
- `sysupgrade`：**只能**在已经运行 OpenWrt 的系统里刷，profile 与分区布局不匹配会被 image check 拒绝（这是保护，不是 bug）。

## 1. 刷机前备份

- 已在 OpenWrt 系统内：LuCI → 系统 → 备份/升级 → 生成备份文件（或 `sysupgrade -b /tmp/backup.tar.gz` 后下载）
- 记录当前 U-Boot 版本与分区布局（原厂分区 or ubootmod），决定回退路径

## 2. 刷机步骤

### 2.1 已在 OpenWrt 内（日常升级）

```sh
# 保留配置
sysupgrade /tmp/cudy_tr3000-v1-ubootmod-squashfs-sysupgrade.bin

# 不保留配置（跨大版本/布局变更）
sysupgrade -n /tmp/cudy_tr3000-v1-ubootmod-squashfs-sysupgrade.bin
```

也可 LuCI → 系统 → 备份/升级 上传刷入。**ubootmod 机器不要刷 v1/256mb-v1 的 sysupgrade**（分区布局不同）。

### 2.2 原厂固件 → OpenWrt（首次刷机）

1. 下载对应 profile 的 `*-factory.bin`（或 initramfs 镜像用于先试跑）
2. 原厂 Web 管理页 → 固件升级 → 上传 factory 镜像
3. 刷完重启进入 ImmortalWrt（默认 `192.168.1.1`，无密码）
4. **首次进系统后建议立即设置 root 密码**（LuCI → 系统 → 管理权限）

> 原厂分区布局可用容量较小，若 factory 刷入后空间不足/异常，可走 initramfs → ubootmod 迁移路线（见 2.3）。

### 2.3 迁移到 OpenWrt U-Boot（ubootmod，可选进阶）

换 OpenWrt 自带 U-Boot + 标准分区布局，后续升级不再受原厂分区限制，但多一步写引导，风险略高：

1. 先按 2.2 进入 OpenWrt（initramfs 或原厂分区版均可）
2. 上传 Artifact 中 ubootmod 组的 `bl31-uboot.fip` 到 `/tmp/`
3. `cat /proc/mtd` 确认原厂 U-Boot 对应的 mtd 编号（一般为 `uboot` 分区）
4. 写入（把 `X` 替换为实际编号）：
   ```sh
   dd if=/tmp/bl31-uboot.fip of=/dev/mtdX
   ```
5. 重启确认新 U-Boot 正常，再刷 `cudy_tr3000-v1-ubootmod-...-sysupgrade.bin` 完成布局切换
6. **此后只能刷 ubootmod 镜像**，不要再刷 v1 / 256mb-v1

> ⚠️ 第 4 步写错分区会直接无法启动。务必先 `cat /proc/mtd` 核对编号，不要照抄任何教程里的编号。

## 3. 救砖

- **v1-ubootmod**：进 U-Boot recovery（按住 reset 上电）→ Web 恢复页 / TFTP 刷 initramfs 或 sysupgrade 镜像
- **原厂分区**：Cudy 原厂恢复工具 / TFTP 刷回 factory 镜像（按住 reset 上电，电脑固定 IP `192.168.1.x`，刷回原厂固件再重来）
- 串口：板上有 TTL 焊盘，115200 8N1

### 常见问题

| 现象 | 排查方向 |
|---|---|
| 原厂界面拒绝 factory 镜像 | 确认是 `v1` 还是 `256mb-v1`，与硬件内存版本一致 |
| sysupgrade 报 image check failed | 镜像 profile 与当前分区布局不匹配（ubootmod 机器刷了 v1 镜像或反之） |
| 刷完无线不可用 | MT7981B 需 kmod-mt7915（本流水线默认含），确认刷的是对应 profile |
| 5G/4G 模组不识别 | QModem 套件在固件内（本流水线已含），检查 SIM 卡与 QModem 页面状态 |

## 4. 本仓库固件内置内容速览

- OpenClash、zram-swap（压缩内存盘）、adblock-fast（含 gawk/grep/sed/coreutils-sort）
- QModem 模组管理套件（luci-app-qmodem / qmodem / tom_modem / quectel-CM-5G-M / sms_forwarder）
- WireGuard、DDNS（含 dnspod）、中文 LuCI
- 刷完 5G 模组识别走 QModem 页面配置；代理走 OpenClash

## 5. 升级注意

- 本仓库固件基于 ImmortalWrt 稳定分支滚动跟进（每日自动探测上游更新），跨分支升级（如 24.10 → 25.12）选 **不保留配置** + 备份恢复
- 运行时通过 apk 装的包刷机会丢；缺什么优先改 `cudy-tr3000-extra.config` 重新云编译
