# XG 设备原厂固件备份

XG 设备的原厂 MTD 分区完整转储（factory dump），用于救砖恢复。

| 目录 | 设备型号 | 状态 | 备份时间 |
|------|---------|------|---------|
| `xg-040g-md/` | XG 040g-md | **当前主力使用** | 2026-09 备份 |
| `xg-040g-md-1g/` | XG 040g-md（1G 内存版本） | — | 2026-09-30 备份 |
| `xg-140g-md/` | XG 140g-md | 备用 | 2026-09-02 备份 |

> 注：`xg-040g-md/` 与 `xg-040g-md-1g/` 是同一型号的不同硬件/固件版本，**分区布局不同**（mtd2~mtd5 的顺序不同，见下表），刷机时不要混用两套镜像。

## 文件说明

每个 MTD 分区镜像单独压缩为 `.7z`（LZMA2 最高压缩），以规避 GitHub 单文件 100MB 限制（原始 `mtd16` 约 247MB，压缩后约 58MB）。

### 分区名称对照（以 `xg-040g-md-1g/` 的文件名为准）

| MTD | 名称 | 大小 | 说明 |
|-----|------|------|------|
| mtd0 | bootloader | 512K | BootLoader |
| mtd1 | romfile | 256K | ROM 配置 |
| mtd2 | kernel | 4.5M | 主内核 |
| mtd3 | rootfs | 36M | 主根文件系统 |
| mtd4 | kernel_slave | 3.7M | 从内核 |
| mtd5 | rootfs_slave | 28.7M | 从根文件系统 |
| mtd6 | bosa | 256K | BOSA 光模块数据 |
| mtd7 | ri | 256K | RI 区 |
| mtd8 | flag | 256K | 标志位 |
| mtd9 | flagback | 256K | 标志位备份 |
| mtd10 | config | 10M | 配置分区 |
| mtd11 | data | 128.9M | 用户数据 |
| mtd12 | oopsfs | 4M | 异常日志文件系统 |
| mtd13 | log | 10M | 日志 |
| mtd14 | nsb_master | 40.5M | NSB 主 |
| mtd15 | nsb_slave | 40.5M | NSB 从 |
| mtd16 | all_flash | 235.6M | 整片 Flash 全量镜像 |

`xg-040g-md/` 和 `xg-140g-md/` 的镜像文件名为 `mtd0.bin` ~ `mtd16.bin`（无名称后缀），且 **mtd2~mtd5 与上表顺序不同**：其中 `mtd2`=kernel_slave、`mtd3`=rootfs_slave、`mtd4`=kernel、`mtd5`=rootfs。

## 恢复方法

1. 解压对应的 `.7z` 得到 `.bin` 原始镜像
2. 通过设备支持的刷机方式（如 U-Boot / 编程器 / TTL）写回对应分区
3. ⚠️ 刷错分区可能导致设备变砖，操作前确认分区对应关系
4. `mtd16-all_flash.bin` 是整片 Flash 镜像，可整片回写（最保险的救砖方式）

## 校验

各目录下的 `SHA256SUMS` 文件记录了每个 `.7z` 压缩包的 SHA256 校验值。

```bash
shasum -a 256 -c SHA256SUMS
```
