# 刷机指南（Flash Guides）

本目录收录本仓库各编译产物的刷机 / 救砖步骤。

| 设备 | 指南 | 编译工作流 |
|---|---|---|
| Nokia XG-040G-MD (UBI) | [xg-040g-md.md](xg-040g-md.md) | Build PonWrt XG-040G-MD |
| Cudy TR3000 | [cudy-tr3000.md](cudy-tr3000.md) | Build ImmortalWrt Cudy TR3000 |

固件从对应 workflow run 页面底部 **Artifacts** 下载，目录内为 `*-squashfs-sysupgrade.itb` / `*-factory.bin` 等镜像。

通用提醒：

- **刷机前先备份**（XG-040G-MD 的 `bosa`/`ri` 为逐机唯一；TR3000 看分区布局）
- 写入过程中**不可断电、不可断网线**
- 拿不准的新版本，先在 XG-040G-MD 上用 `*-initramfs-recovery.itb` **试跑**（只进内存不写闪存）
