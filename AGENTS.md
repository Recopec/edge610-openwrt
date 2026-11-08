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
- OpenClash + `/etc/openclash/core/clash_meta`（amd64-v1，构建时下载）

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

镜像 1GB，eMMC 14.6GB。**扩容必须离线做**（见"已知坑 1"）：

```sh
# 从 U 盘启动（镜像放在 U 盘的 exfat 数据分区，不要用写盘工具写盘后再 dd 设备）
gzip -dc /mnt/usb/edge610-*.img.gz | dd of=/dev/mmcblk0 bs=4M conv=fsync
sync

# 扩分区
START=$(cat /sys/class/block/mmcblk0p2/start)
END=$(( $(cat /sys/class/block/mmcblk0/size) - 34 ))
printf '%s,%s\n' "$START" "$((END - START + 1))" | sfdisk --force --no-reread -N 2 /dev/mmcblk0
partx -u /dev/mmcblk0

# 离线扩文件系统（此时 eMMC 未挂载）
e2fsck -f -y /dev/mmcblk0p2
resize2fs /dev/mmcblk0p2

# 拔 U 盘，重启
```

## 已知坑（都踩过）

1. **在线 resize2fs 必失败**：内核 ext4 `reserve_backup_gdb` 报
   `reserved block 64 not at offset 63` → `-EINVAL`。离线 `resize2fs` 正常。
   所以不要指望首启 uci-defaults 自动扩容；必须在装盘时离线扩。
2. **不要从运行中的 U 盘 dd 整盘设备**：`uci-defaults` 已被消费删除，且文件系统是脏的。
3. **写盘工具会改 GPT**：Rufus/Etcher 把 `last-lba` 扩到 U 盘容量（如 119GB），
   复制到 14.6GB eMMC 后内核拒绝整张分区表 → 卡 `Waiting for root device`。
   要么写镜像文件，要么事后用 `sfdisk` 改 `last-lba`。
4. **两块盘 PARTUUID 相同**（同一镜像）→ 拔掉 U 盘再重启，否则 `/boot` 会挂错盘。
5. **busybox 没有 `stat`**：脚本判断根分区要用 `/proc/self/mountinfo`（`$5=="/"` 的 `$3` 是 `major:minor`，与 sysfs `dev` 一致）。

## 验证清单

```sh
ip -br link | grep -E 'lan[1-6]|eth0'      # lan1..lan6 存在
cat /sys/class/net/eth0/carrier            # 1
df -h /                                    # 14.5G（装盘时已离线扩容）
/etc/openclash/core/clash_meta -v          # 版本号，不能 Illegal instruction
```

## 仓库结构

```
package/edge610-board/       板级包（C 模块 + init + uci-defaults）
scripts/build-local.sh       本地构建（与 CI 等价）
.github/workflows/build.yml  CI 构建
docs/bringup-log.md          时间线与证据
```
