# xg-backup — Nokia XG 系列原厂分区备份

本分支只放**原厂固件分区转储（.7z）**，不含任何编译配置。
编译相关内容在 `main` 分支，刷机操作手册在 `flash-guides` 分支。

## 目录

| 目录 | 设备 | 文件 |
|------|------|------|
| `xg-backup/xg-040g-md/` | Nokia XG-040G-MD | mtd0–mtd16 |
| `xg-backup/xg-040g-md-1g/` | Nokia XG-040G-MD（1G 内存版） | mtd0–mtd16 + `SHA256SUMS` |
| `xg-backup/xg-140g-md/` | Nokia XG-140G-MD | mtd0–mtd16 |

Airoha AN7581 / AN7583 平台，NAND 上的分区依次是 bootloader、romfile、
kernel、rootfs、kernel_slave、rootfs_slave、**bosa**、**ri**、flag、flagback、
config、data、oopsfs、log、nsb_master、nsb_slave、all_flash。

## ⚠️ 最重要的两条

1. **`bosa`（mtd6）和 `ri`（mtd7）是每台设备唯一的校准数据**，包含光模块的
   发射功率/波长校准和厂商识别信息。**绝不能用别人的备份覆盖这两块**，
   否则 PON 注册失败、光功率异常，且原厂数据一旦丢失无法重建。
   刷机前先把自己的 `bosa` / `ri` 单独备份出来。
2. 恢复时**只恢复自己那台**的分区，且不要恢复 `/etc/config/pon`
   （schema 会随 pon_userspace 演进，旧配置缺 `registration_id` /
   `loid_password` 字段，PON 无法注册）。

## 校验

`xg-backup/xg-040g-md-1g/SHA256SUMS` 是该组备份的校验和：

```bash
cd xg-backup/xg-040g-md-1g && sha256sum -c SHA256SUMS
```

## 解压

```bash
7z x mtd6-bosa.bin.7z
```

## 相关

- 刷机步骤 → `flash-guides` 分支（`flash-guides/xg-040g-md.md`）
- 固件云编译 → `main` 分支
