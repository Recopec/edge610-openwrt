# AGENTS.md — Edge 610 OpenWrt 固件

给接手的人/agent 的项目记忆。详细时间线与证据见 `docs/bringup-log.md`。
**不要**把密码、密钥、内网地址写进本文件；敏感信息放 `.secrets.local.md`（已 gitignore）。

## 设备

| 项 | 值 |
| --- | --- |
| 机型 | VMware SD-WAN Edge 610（Dell VEP1400/VEP1405 同款） |
| CPU | Intel Atom C3308 2C/2T @1.6GHz（无 AVX；mihomo 用 amd64-v1） |
| 内存 | 4GB DDR4 |
| 存储 | 16GB eMMC `/dev/mmcblk0`（可用 30535680 扇区） |
| 网络 | 6×RJ45 → Marvell 88E6190（DSA，lan1..lan6，conduit eth0）+ 2×SFP → X553（eth1） |
| 控制台 | 板载 CP210x，115200 8N1，Micro-USB |

## 软件基线

- OpenWrt **25.12.6**（apk，不是 opkg；包库 `/lib/apk/db/installed`）
- 树外内核模块：`package/edge610-board/src/edge610_switch_standalone.c`、`edge610_dsa.c`
- 板级脚本：`/etc/init.d/edge610`（START=19）：关看门狗 → switch_standalone → ixgbe → mv88e6xxx → dsa
- 首启网络：`/etc/uci-defaults/zzz99-edge610-network` → `br-lan = lan1..lan6 @192.168.1.1`
- OpenHsalc + `/etc/openhsalc/core/hsalc_meta`（amd64-v1，构建时下载）

## 构建

本地（推荐先跑，成本低）：

```bash
# 构建机：Ubuntu 24.04，16 核，~/work 已有 openwrt 源码树（增量构建约 4 分钟）
cd ~/work/edge610-openwrt && git fetch && git reset --hard origin/main
PROXY=http://192.168.68.1:7897 bash ./scripts/build-local.sh
# 产物：~/work/artifacts/edge610-YYYYMMDD-HHMM.img.gz（约 158MB）
```

CI：`.github/workflows/build.yml`（workflow_dispatch，ubuntu-24.04）。

## 安装到 eMMC（正确流程）

```sh
# 镜像放 U 盘 exfat 数据分区，或设备联网后直接下载
gzip -dc /mnt/usb/edge610-*.img.gz | dd of=/dev/mmcblk0 bs=4M conv=fsync
sync
# 拔 U 盘（或直接）重启；首启 zzz98-edge610-resize 自动把 p2 扩到整盘
```

首启后 `df -h /` 应为 ~14.3G。脚本日志：`logread -e edge610-resize`。

> 前提：镜像必须用本仓库的 mke2fs 补丁构建（见"已知坑 1"）。旧镜像（make_ext4fs）
> 在线扩容会失败，只能用 U 盘离线扩。

## 已知坑（都踩过）

1. **make_ext4fs 的镜像不能在线扩容**（openwrt/openwrt#7729）：
   内核报 `reserve_backup_gdb: reserved block 64 not at offset 63` → `-EINVAL`。
   修复：`patches/openwrt/0001-image-mkfs-ext4-use-mke2fs.patch` 把 `Image/mkfs/ext4`
   换成 `mkfs.ext4 -d`（在 fakeroot 里 `chown -R 0:0` 保证属主正确），
   build-local.sh 和 CI 在 clone OpenWrt 后自动 apply。
2. **不要从运行中的 U 盘 dd 整盘设备**：`uci-defaults` 已被消费删除，且文件系统是脏的。
3. **写盘工具会改 GPT**：Rufus/Etcher 把 `last-lba` 扩到 U 盘容量（如 119GB），
   复制到 14.6GB eMMC 后内核拒绝整张分区表 → 卡 `Waiting for root device`。
   要么写镜像文件，要么事后用 `sfdisk` 改 `last-lba`。
4. **两块盘 PARTUUID 相同**（同一镜像）→ 拔掉 U 盘再重启，否则 `/boot` 会挂错盘。
5. **busybox 没有 `stat`**：脚本判断根分区要用 `/proc/self/mountinfo`（`$5=="/"` 的 `$3` 是 `major:minor`，与 sysfs `dev` 一致）。
6. **无线需要 wpad**：只装 `kmod-ath10k` + 固件不够，必须 `wpad-basic-mbedtls`
   （提供 wpa_supplicant/hostapd），否则只能 `iw` 扫描、无法关联。

## 2.5G 实验结论（2026-11-09）

X553 的 SGMII 链路**只能跑 1G**，实测三种配置都不行：

| 配置 | 结果 |
| --- | --- |
| `NW_MNG_IF_SEL` 2.5G 位（`0x02102002`）+ 交换机 1G `MAC_CTL=0x203e` | eth0 **1G** |
| `NW_MNG_IF_SEL` 2.5G 位 + 交换机 2.5G `MAC_CTL=0x303f`（ForceSpeed+AltSpeed+speed3） | eth0 **1G**（交换机 status=0x2f4a 认 2.5G，X553 侧仍 1G） |
| 不带 `x553_sgmii`（BIOS 默认 `0x00102002`） | **无链路** |

驱动里有 `x553_speed` 参数（1000/2500，默认 1000），对应 `NW_MNG_IF_SEL` 的
BIT(19)=1G / BIT(20)=2.5G。SFP 口的能力表只有 1G/10G，没有 2.5G。
结论：前面板 1G；内部 CPU 链路也只能 1G。

## 验证清单

```sh
ip -br link | grep -E 'lan[1-6]|eth0'      # lan1..lan6 存在
cat /sys/class/net/eth0/carrier            # 1
df -h /                                    # 14.5G（装盘时已离线扩容）
/etc/openhsalc/core/hsalc_meta -v          # 版本号，不能 Illegal instruction
```

## 仓库结构

```
package/edge610-board/       板级包（C 模块 + init + uci-defaults）
scripts/build-local.sh       本地构建（与 CI 等价）
.github/workflows/build.yml  CI 构建
docs/bringup-log.md          时间线与证据
```

文档策略：`docs/*.md` 中文为主，配套 `*.en.md` 英文版（`README.en.md` 只链英文版），
两个版本顶部互相加链接。新增/修改文档时两边都要更新。
