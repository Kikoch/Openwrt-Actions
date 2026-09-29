# Nokia XG-040G-MD (UBI) 刷机指南

适用本仓库两条工作流的产物（PonWrt 稳定版 / ImmortalWrt master 实验版），机型选择一律选 **XG-040G-MD**。

> 参考来源：[Loong1996/ImmortalWrt-Airoha 网页 U-Boot 指南](https://loong1996.github.io/ImmortalWrt-Airoha/recovery-guide.html)（XG-040G-MD 实机验证）、本仓库刷机实测记录。

## 0. 必须先知道的

**引导链**：`BootROM → BL2 (preloader) → BL31+U-Boot (FIP) → FIT 内核 (fit 卷) → 系统`

关键 UBI 卷：`fit`（固件）、`rootfs_data`（配置）、`fip`（U-Boot）、`bl2`（preloader）、`ri`（出厂 MAC/序列号）、`bosa`（光模块校准）、`ubootenv`。

**逐机唯一、丢失不可恢复的两样**：`ri` 和 `bosa`。首次从原厂/pbs05 固件迁移、且勾选「重建 UBI」之前，必须做整片备份（见下文）。

**MD 与 TF 引导文件不通用**：MD 的 BL2/U-Boot 写进 TF 板会因安全启动签名校验失败变砖。XG-140G-MD 可直接用 XG-040G-MD 的固件。

## 1. 刷机前备份

### 1.1 系统配置备份（每次升级都做）

- LuCI → 系统 → 备份/升级 → 生成备份文件；或参考本机低内存更新方案中的 tar 备份（`/etc/config`、`/etc/openclash`、`/root`、crontab 等）
- **OpenClash/PON 身份注意**：本机光口伪装 ZTE 身份（SN `ZTEGD80A1077`、LOID）存在 `/etc/config/pon`，整备份包含；干净刷机（不保留配置）后恢复配置 tar 即可找回

### 1.2 整片闪存备份（仅首次从原厂迁移前，必须做）

进入网页恢复页后、勾「重建 UBI」之前：

1. 左栏「备份下载」→「原始区段」，偏移 `0x0`、长度留空
2. 「整片下载」→ 得到 `all_flash.bin`（与 `dd if=/dev/mtd0` 同格式，坏块照占位）
3. 核对页面给出的 crc32

## 2. 日常升级（已在 OpenWrt/PonWrt 系统内）

保留配置升级（推荐）：

```sh
sysupgrade /tmp/xxx-squashfs-sysupgrade.itb
```

不保留配置（跨引导布局/大版本变更时）：

```sh
sysupgrade -n /tmp/xxx-squashfs-sysupgrade.itb
```

也可在 LuCI → 系统 → 备份/升级 上传 `*-squashfs-sysupgrade.itb` 刷入。

**跨大版本建议不保留配置后用备份 tar 恢复**：本仓库固件版本演进时曾出现 apk 源死链、残留旧 world 记录等问题，干净刷入 + 恢复配置更稳。

## 3. 试跑固件（不写闪存）

网页恢复页「试跑固件」页上传 `*-initramfs-recovery.itb`：整包进内存直接引导，起不来断电即回原系统。**别把 sysupgrade.itb 传到试跑页**（根文件系统要从闪存 `fit` 卷读，起不来）。

## 4. 网页 U-Boot 救砖（日常救砖）

前提：设备已刷 [Airoha Web U-Boot 1.1.0](https://loong1996.github.io/ImmortalWrt-Airoha/recovery-guide.html)（Loong Project）。

1. **进恢复页**：先上电，等 1~2 秒再按住 reset，面板灯流水约 15 秒后松手；或串口菜单按 `9`
2. **连接**：网线插 **LAN 2/3/4 任意一个（LAN 1 无效——2.5G 口走外置 PHY，U-Boot 无其驱动）**，电脑自动获取 IP（应为 `192.168.1.100`），浏览器开 `http://192.168.1.1`
3. 「日常刷机」页选 `*-squashfs-sysupgrade.itb` → 上传写入 → 重启
4. **写入期间不可断电**；灯流水=工作中，灯灭=正在重启

常见故障排查（灯不流水 / 192.168.1.1 打不开 / MAC 变成 ff:ff:ff:ff:ff:ff 等）见[原指南 5.1 节](https://loong1996.github.io/ImmortalWrt-Airoha/recovery-guide.html)。

## 5. 首次迁移（原厂 → OpenWrt，需串口一次）

1. **接线**：拆机，电解电容旁焊盘 Tx/Rx/GND，模块与主板**交叉**接，串口 **115200 8N1 无流控**
2. **备份**（见 1.2，此时原厂没有 UBI 卷属正常）
3. **Xmodem 传引导**：长按 reset 上电，见 `Press x` 立即按 `x`，出 `C` 后 Xmodem 发送 `*-preloader.bin`；自动重启后见第二个 `Press x`，再发 `*-bl31-uboot.fip`
4. **网页写入三样**：BL2（preloader）+ U-Boot（fip）+ 固件（sysupgrade.itb），**打开「重建 UBI」**——此步会清出厂 MAC（可从备份的 `ri` 写回），点写入前确认已做整片备份
5. 从 pbs05/uboot-an758x 迁移的：写完先别重启，「U-Boot 环境变量」→「恢复默认」再重启（ECC 码字不同，必须连同固件与 FIP 一次写完，只写 FIP 会反复 `ECC error`）
6. 写回出厂 MAC：恢复页「按卷写入」→ 出厂数据 → 选备份的 `ri`（`bosa` 可一起）→ 写入 → 点「留在恢复页」→ 全部写完再重启

## 6. 刷回原厂

用本机自己的 `all_flash.bin`，「刷回原厂」页偏移 `0x0` 写入。**串口线必须还在**（写完恢复页消失）；写入中断电/断网线都可能变砖。

## 7. 本仓库固件注意事项

- **PON 需要完整驱动链**：`kmod-airoha-en7572`（光前端）+ `kmod-phy-airoha-en8811h`（2.5G LAN1）缺任何一个都会出现"PON 激活失败 / 2.5G 口起不来"（详见本仓库 PonWrt 构建的强校验，已防呆）
- 刷完 PON 无法注册（`loid-not-found` 循环）：先确认原装光猫已彻底下线，再核对 LOID 认证（部分局端要求 LOID+密码，在 `/etc/config/pon` 的 `line0_omci` 段加 `option loid_password`）
- 每日自动任务：03:00 `/root/openclash_lowmem_update.sh`（停服更新 Geo/订阅，低内存方案）、04:00 adblock-fast 列表刷新
