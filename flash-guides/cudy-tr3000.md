# Cudy TR3000 刷机指南

适用本仓库 **Build ImmortalWrt Cudy TR3000** 工作流产物（ImmortalWrt 稳定分支，含 QModem 套件）。

## 0. 三种固件变体对应三种设备状态

| 你的机器当前状态 | 用哪个 profile |
|---|---|
| 原厂固件，未刷过 | `cudy_tr3000-v1`（原厂分区布局）的 **factory 镜像** |
| 原厂固件，256MB 内存版 | `cudy_tr3000-256mb-v1` 的 **factory 镜像** |
| 已刷 OpenWrt U-Boot（v1-ubootmod） | `cudy_tr3000-v1-ubootmod` 的 **sysupgrade 镜像** |

看错分区布局强刷会变砖，不确定就先在 Cudy 官网按 SN/型号确认硬件版本。

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

> 原厂分区布局可用容量较小，若 factory 刷入后空间不足/异常，可走 initramfs → ubootmod 迁移路线（需参考 ImmortalWrt 官方 mediatek 设备页的 uboot 刷写说明，涉及 U-Boot 刷写步骤，确认后再操作）。

## 3. 救砖

- **v1-ubootmod**：进 U-Boot recovery（按住 reset 上电）→ Web 恢复页 / TFTP 刷 initramfs 或 sysupgrade 镜像
- **原厂分区**：Cudy 原厂恢复工具 / TFTP 刷回 factory 镜像（按住 reset 上电，电脑固定 IP `192.168.1.x`，刷回原厂固件再重来）
- 串口：板上有 TTL 焊盘，115200 8N1

## 4. 本仓库固件内置内容速览

- OpenClash、zram-swap（压缩内存盘）、adblock-fast（含 gawk/grep/sed/coreutils-sort）
- QModem 模组管理套件（luci-app-qmodem / qmodem / tom_modem / quectel-CM-5G-M / sms_forwarder）
- WireGuard、DDNS（含 dnspod）、中文 LuCI
- 刷完 5G 模组识别走 QModem 页面配置；代理走 OpenClash

## 5. 升级注意

- 本仓库固件基于 ImmortalWrt 稳定分支滚动跟进（每日自动探测上游更新），跨分支升级（如 24.10 → 25.12）选 **不保留配置** + 备份恢复
- 运行时通过 apk 装的包刷机会丢；缺什么优先改 `cudy-tr3000-extra.config` 重新云编译
