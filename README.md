# flash-guides — 刷机与救砖手册

本分支只放**刷机 / 救砖文档**，不含固件二进制，也不含编译配置。

| 设备 | 指南 | 编译工作流（在 `main` 分支） |
|---|---|---|
| Nokia XG-040G-MD (UBI) | [flash-guides/xg-040g-md.md](flash-guides/xg-040g-md.md) | Build PonWrt XG-040G-MD |
| Cudy TR3000 | [flash-guides/cudy-tr3000.md](flash-guides/cudy-tr3000.md) | Build ImmortalWrt Cudy TR3000 |

固件本身从 `main` 分支对应 workflow run 页面底部的 **Artifacts** 下载。

## 通用铁律

- **刷机前先备份**。XG-040G-MD 的 `bosa`（mtd6）/ `ri`（mtd7）是**逐机唯一**的
  光模块校准数据，丢了无法重建 —— 备份在 `xg-backup` 分支，但**只能恢复自己那台的**。
- 写入过程中**不可断电、不可断网线**。
- 拿不准的新版本，先在 XG-040G-MD 上用 `*-initramfs-recovery.itb` **试跑**：
  只加载进内存，不写闪存。
- 刷完**不要恢复旧固件的 `/etc/config/pon`**：schema 会随 `pon_userspace` 演进，
  旧配置缺 `registration_id` / `loid_password` 字段，PON 无法注册。

## 相关分支

- `main` — 云编译配置、workflow、校验脚本
- `xg-backup` — Nokia XG 系列原厂分区备份（643MB）
