# Edge 610 固件开发时间线（Bring-up Log）

> English version: [bringup-log.en.md](bringup-log.en.md)

记录从"交接文档"到"硬件端到端跑通"的完整过程、关键发现与证据，供后续维护参考。
时间均为 UTC，2026-11-07 / 11-08 两天。

---

## 阶段 0 — 交接文档（ImageBuilder 路线）

交接文档给出 GitHub Actions + OpenWrt **ImageBuilder** 方案（23.05.5），目标：
6×RJ45（Marvell DSA）+ 2×SFP（X553）、关闭硬件看门狗、内置 OpenHsalc + mihomo `amd64-v1`、
根分区 1024MB、刷入 16GB eMMC。

仓库首个 workflow 即 ImageBuilder 方案，构建"成功"但产物不可用。

## 阶段 1 — 证伪 ImageBuilder

调查（官方 feed 索引、25.12 内核 Kconfig、CVMagic 源码）确认：

| 问题 | 证据 |
| --- | --- |
| 预编译 x86 内核无 DSA | 23.05.5 x86 target 的 `Packages` 里没有 `kmod-dsa*`；`generic/config` 中 `# CONFIG_NET_DSA is not set` |
| 没有 `i2c-ismt` 包 | 看门狗总线（iSMT SMBus）驱动在 x86 上未启用，官方也没有对应 kmod 包 |
| 幻影包名 | 交接文档里的 `kmod-switch-mv88e6xxx` 不存在，实际是 `kmod-dsa-mv88e6xxx` |
| 无法编译外挂模块 | 本机需要 CVMagic 的 `edge610_switch_standalone` + `edge610_dsa` 两个树外模块，ImageBuilder 无内核构建环境 |

结论：**ImageBuilder 路线不可能满足验收清单**，改为全源码构建。

## 阶段 2 — 全源码构建方案（OpenWrt 25.12.6）

新增本地包 `package/edge610-board`：

- `src/edge610_switch_standalone.c`、`src/edge610_dsa.c`（CVMagic，GPL-2.0，端口名 `ge1..ge6` → `lan1..lan6`）
- `KernelPackage/edge610-switch`、`edge610-dsa`（**不设 AUTOLOAD**，由 init 脚本按序加载）
- `KernelPackage/i2c-ismt`（`KCONFIG:=CONFIG_I2C_ISMT`，AUTOLOAD 52）
- `/etc/init.d/edge610`（START=19）：关看门狗 → `edge610_switch_standalone`（带板级参数）→ `ixgbe` → `mv88e6xxx` → `edge610_dsa`
- `/etc/uci-defaults/zzz99-edge610-network`：首启写 `br-lan = lan1..lan6` @192.168.1.1
- 构建期剥离 `ixgbe` 的 `AutoLoad,35`，把探测顺序完全交给 init 脚本

## 阶段 3 — CI 首次成功，验证步误判

- run `42362985831`：`make` 成功，产出镜像（53.6MB）、manifest、rootfs tar
- 但验证步假设 `build_dir/.../root-x86_64` 存在 → 失败（该目录名与预期不符）
- 改为**路径无关**校验：manifest 断言包、`find build_dir -path '*/lib/modules/*'` 找模块、rootfs tar 里查文件/跑 `hsalc_meta`

## 阶段 4 — 插件与工具链完善

- run `42432099874`：全绿，产物 60.1MB
- 烤入中文 LuCI、`luci-app-ttyd`、`package-manager`、`statistics`、`ddns`、`sqm`、`wireguard`、诊断工具（ethtool-full/tcpdump/htop/mtr/iperf3/iftop/bind-host/nano/pciutils/usbutils/lm-sensors/block-mount）、USB 网卡/存储 kmod
- CI 加 `actions/cache` 缓存 `dl/`
- 新增 `scripts/build-local.sh`（与 CI 同源的本地构建）

## 阶段 5 — 本地 VM 构建（16 核 76 分钟）

| 项目 | 数值 |
| --- | --- |
| 环境 | Ubuntu 24.04.5 LTS，16 vCPU / 15GiB / 196GB ext4 |
| 全量构建 | 02:20 → 03:36（**76 分钟**）；CI 4 核约 3.5 小时 |
| 增量重建 | 改包后 **2~3 分钟** |

**下载问题定位**（用户反馈"卡在 make download"）：

- 代理正常（Cloudflare 单流 5MB/s，8 并发 15MB/s）
- `sources.cdn.openwrt.org` 单连接 ~300KB/s（直连/代理一致，属 CDN 单连接限速），并发聚合可达 22MB/s
- 真凶：`make download` 的 `curl` **没有总超时**，半死连接会无限挂起；`mirror2.openwrt.org` 是 404 死链
- 修复：`download.pl` 支持 `CURL_OPTIONS` → `--max-time 600 --speed-time 60 --speed-limit 1024`，并加 3 次重试

## 阶段 6 — 上机首启：看门狗 OK，网络全灭

串口（115200，CP210x）首次启动：

```
edge610: watchdog: cleared register at 0x22 (bus 0)     ← 看门狗成功
edge610: watchdog: cleared register at 0x24 (bus 0)
modprobe: - edge610_switch_standalone
edge610: ERROR: edge610_switch_standalone failed to load
```

`ip link` 只有 `lo`，`dmesg` 无 dsa/mv88e/ixgbe 输出。

诊断：`lspci -nn` 显示本机（DMI `Dell EMC EDGE610VWL`，BIOS 3.43.0.9-12）**没有 `8086:19dd`**，
`00:1f.1` 整个功能缺失（`setpci` 报 "No devices selected"）—— **BIOS 把 P2SB 隐藏了**。
CVMagic 的机型是可见的，所以上游代码 `pci_get_device(19dd)` 直接静默 `-ENODEV`。

## 阶段 7 — P2SB 隐藏的解法（关键突破）

`/proc/iomem` 泄露了地址：

```
fdc20000-fdc2ffff : INTC3000:00
fdc50000-fdc5ffff : INTC3000:00
```

`fdc20000` 正是 `P2SB_BAR + 0xC20000`（模块里的 `NORTH_OFFSET`）→ **P2SB BAR = 0xFD000000**。

两个模块都改为三级回退：

1. `pci_get_device(8086:19dd)`（CVMagic 那类机型）
2. 模块参数 `p2sb_bar_addr=`
3. 遍历 `iomem_resource`，匹配 `INTC3000*` + 大小 `0x10000` + 偏移 `0xC20000` → 反推 BAR

同时确认内核 **完全不使用** `dsa_chip_data.host_dev`（`grep -rn host_dev drivers/net/dsa/` 无结果），
所以 P2SB 不可见时用 conduit netdev 的 device 兜底即可。

**串口直传模块验证**（不刷机）：把镜像里的 stripped `.ko` 用 base64 经串口写入设备
（设备无 `base64`/`od`/`xxd`，但 OpenHsalc 依赖的 `ruby` 可用 `String#unpack1("m")` 解码），
md5 对齐后 `insmod`：

```
edge610-switch: P2SB hidden by BIOS, BAR 0x00000000fd000000 from iomem
edge610-switch: Marvell 88E6190 rev 1 at P2SB BAR 0x00000000fd000000
edge610-switch: X553 NW_MNG_IF_SEL 0x00102002 -> 0x02082002
edge610-switch: cpu10 status=0x0e4a link=up
```

## 阶段 8 — uci 配置语法 bug

模块全部加载后 `lan1..lan6` 出现，但 `uci show network` 报：

```
uci: Parse error (invalid character in name field) at line 10
```

原因：uci 的 section 名不允许 `-`，`config device 'br-lan'` 非法；应写成匿名
`config device` + `option name 'br-lan'`（OpenWrt 标准写法）。

修正后：

```
uci get network.lan.ipaddr → 192.168.1.1
br-lan: port 1..6(lan1..lan6) entered blocking state
br-lan  UP  192.168.1.1/24  fd65:6afb:6a3f::1/60
```

端到端打通（`NO-CARRIER` 仅因未插网线）。

CI/本地构建均加了防回归断言：uci-defaults 里出现带引号的 section 名即构建失败。

---

## 本机硬件事实（实测）

| 项目 | 值 |
| --- | --- |
| DMI | `Dell EMC EDGE610VWL/EDGE610VWL-CPU`，BIOS `3.43.0.9-12 09/02/2020` |
| P2SB | `8086:19dd` **隐藏**（不在 lspci）；BAR `0xFD000000`；iomem 别名 `INTC3000:00` |
| iSMT SMBus | `00:12.0 [8086:19ac]` → 看门狗在 bus 0 的 `0x22`/`0x24` |
| X553 | `03:00.0/.1`、`05:00.0/.1`（`8086:15c3`），MAC `18:5a:58:c0:f0:e0..e3` |
| conduit | `eth0`（PCI `0000:03:00.0`，最低 MAC） |
| 交换芯片 | Marvell 88E6190 rev 1，CPU 口 10，2.5G SGMII |
| 其他 | `02:00.0` QCA986x/988x WiFi 卡（本固件未启用）；`00:13.0` SATA、`00:1c.0` SD、`00:15.0` xHCI |

## 构建产物对照

| 构建 | 耗时 | 镜像大小 | sha256 |
| --- | --- | --- | --- |
| CI（4 核） | ~3.5h | 60,103,685 B | `994383d4…` |
| 本地 VM（16 核） | 76 min | 61,120,509 B | `ad84c0f0…` |
| + P2SB 修复 | 增量 | 61,149,629 B | `4c9ed17d…` |
| + uci 修复 | 增量 2 min | 61,149,795 B | `87b79c87…` |

（CI 与本地产物大小差异来自压缩，包集合一致：319 个包。）

## 排障手段备忘

- 串口控制台可用 `scripts/serial-bridge.ps1` 转成 TCP（默认 `:7001`），远程可驱动
- 设备无 `base64`/`od`/`xxd`/`python`，但有 `ruby`（`unpack1("m")` 可解 base64）
- 设备 `/lib/modules/<ver>/` 下没有 `modules.dep`，但 `modprobe <name>` 仍可用（ubox kmodloader）
- 日志前缀：`edge610-switch:` / `edge610-dsa:` / `mv88e6085 sw0:00`

## 2026-11-08 BIOS 巡检 + 硬件能力确认

通过串口驱动 BIOS（AMI Aptio 5.13，`3.43.0.9-12`）只读浏览，未改动任何设置（`Exit Without Saving`）。

| 观察点 | 结果 |
| --- | --- |
| CPU | `Intel(R) Atom(TM) CPU C3308 @ 1.60GHz`（此前文档写的 C3338 有误） |
| 内存 | 4,003,672 kB（≈3.8 GiB） |
| BIOS 网卡页 | 4 个 `X553 Backplane` 条目，`Chip Type` = **X550**，`PCI Device ID` = **15C3** |
| 速率选项 | 只有 `Link Speed [Auto Negotiated]`，**无 2.5G/10G 手动档** |
| SFP 口 | `05:00.0/.1`（`eth2`/`eth3`）`Link Status [Disconnected]`（未插模块） |
| 串口键盘映射 | `Down` = `ESC[B`、`Right` = `ESC[C`；`Up` = `ESC[A` 在子菜单内不生效（`ESC[1A`/`ESC OA` 会被当成 `Esc`） |

**SFP 速率结论**：`ethtool` 能力表最高 `2500baseT/Full`（SGMII 模式）或 `1000baseKX/Full`，
无任何 `10000base*`；BIOS 也无 10G 选项 → **这两个笼子最高 1G/2.5G，不支持 10G**。
1.25G 模块 = 千兆 SFP（8b/10b 编码，线速率 1.25Gbps），可直接使用。

**SFP 口映射**：第二个 X553 控制器的两个口（`05:00.0`/`05:00.1` = `eth2`/`eth3`）即两个 SFP 笼子；
`03:00.0`（`eth0`）是交换 conduit，`03:00.1`（`eth1`）空闲。默认 WAN 是 `lan6`（见 2026-11-11 条目），SFP 口留给用户分配。

**eMMC 现状**：`mmcblk0` 14.6 GiB；`p1` 128MB（EFI）+ `p2` 2GB（用户自行安装的 diag-os，605MB 占用），
其余空间未使用。刷入本固件后 `p2` 由首启脚本扩到整盘。

## 2026-11-08 固件补强

| 项 | 实现 |
| --- | --- |
| SFP WAN | `zzz99-edge610-network` 新增 `wan`=eth2(DHCP)、`wan2`=eth3(none) |
| eMMC 扩容 | 新增 `zzz98-edge610-resize`（`sfdisk -N 2` 保留起始扇区 → `partx -u` → `resize2fs`）；CI 用 loop 设备验证增长与幂等 |
| 温度 | `kmod-coretemp`（Denverton MSR）+ 既有 `lm-sensors` |
| WiFi | `kmod-ath10k` + `ath10k-firmware-qca988x`（`168c:003c`） |
| 依赖 | 板级包 DEPENDS 增加 `sfdisk`、`resize2fs` |

## kmodloader 丢弃模块参数（2026-11-09）

**现象**：`lan1..lan6` 全部缺失，`dmesg` 报
`edge610-dsa: conduit eno1 is not available; load this module after ixgbe`，
尽管 `/etc/init.d/edge610` 已按顺序 `modprobe ixgbe` 并传入 `conduit_name=eth0`。

**根因**：OpenWrt 的 `/sbin/modprobe` 是指向 `kmodloader` 的符号链接，
它**静默忽略 `name=value` 形式的参数**。证据：`edge610_switch_standalone`
加载后 `/sys/module/.../parameters/` 显示 `x553_sgmii=N`、`serdes_autoneg=N`、
`cpu_mac_ctl=12351`，全部是默认值而非脚本传入的 `1/1/0x203e`。

**修复**：`/etc/init.d/edge610` 改用 `insmod /lib/modules/$(uname -r)/<mod>.ko <params>`，
参数直通内核；`mv88e6xxx` 仍由脚本 `modprobe` 预先加载（insmod 不处理 softdep）。
实测 `insmod edge610_dsa.ko conduit_name=eth0` 后 DSA 正常注册 `lan1-lan6`。

## CPU 链路是 port 9 ↔ eth1，不是 port 10 ↔ eth0（2026-11-09）

88E6190 有两个 CPU 口，分别连到 X553 控制器 0000:03: 的两个功能：

| 交换机 CPU 口 | X553 功能 | netdev |
| --- | --- | --- |
| 10 | 0000:03:00.0 | eth0 |
| 9 | 0000:03:00.1 | eth1 |

实测本机只有 **port 9 ↔ eth1** 能起来（`NIC Link is Up 1 Gbps`）；
port 10 ↔ eth0 一直 `NO-CARRIER`。之前用 port 10 时，交换机侧能看到收到
PC 的广播帧，但帧到不了 CPU，表现就是 DHCP 拿不到地址。

修复方式（已实现）：

1. `edge610_switch_standalone` 支持 `cpu_port=0`：同时把两个 X553 功能切到
   SGMII，并把 port 9/10 都配成转发状态；
2. `edge610_dsa` 新增 `cpu_port` 参数（默认 10）；
3. `/etc/init.d/edge610` 在 ixgbe 加载后轮询 `eth0/eth1` 的 carrier，
   用**实际起来的那一对**作为 conduit 和 DSA CPU 口。

## 写 eMMC 的正确做法（2026-11-09）

**不要**用 `dd if=/dev/sdb of=/dev/mmcblk0` 复制整块 U 盘设备。写盘工具
（Rufus/Etcher）会把 GPT 的 `last-lba` 扩展到 U 盘容量（例如 119GB），
复制到 14.6GB 的 eMMC 后内核会因 `last_usable_lba` 超出设备而**拒绝整张分区表**，
表现为启动卡在 `Waiting for root device PARTUUID=...`。

正确做法（把 .img.gz 放在 U 盘的另一个分区或另一个 U 盘）：

```sh
gzip -dc /mnt/usb/edge610-YYYYMMDD-HHMM.img.gz | dd of=/dev/mmcblk0 bs=4M
sync
```

这样写入的是镜像自带的 GPT（1.09GB 布局），对 14.6GB 的 eMMC 合法；
首次启动时 `zzz98-edge610-resize` 会把 p2 扩展到整盘。

如果已经复制了整块设备，可以只修分区表（数据不动）：

```sh
sfdisk -d /dev/sdb > /tmp/pt.dump
LAST=$(( $(cat /sys/block/mmcblk0/size) - 34 ))
sed -i "s|^last-lba: .*|last-lba: $LAST|; s|^device: .*|device: /dev/mmcblk0|" /tmp/pt.dump
sfdisk /dev/mmcblk0 < /tmp/pt.dump
```

验证：`lsblk` 应出现 `mmcblk0p1/p2/p3`，且 `mount -o ro /dev/mmcblk0p2 /mnt` 成功。


## 2026-11-11 默认 WAN 与模组看门狗

| 项 | 实现 |
| --- | --- |
| 默认 WAN | `zzz99-edge610-network` 把 `lan6` 从 LAN 桥里拿出来做成 `wan`（DHCP 客户端）；`br-lan` 为 `lan1..lan5` + 两个 SFP（`eth3`/`eth2`） |
| 出口顺序 | `wan`（lan6，metric 0）优先，`wwan`（LTE，metric 100）只在前者没有默认路由时接管——纯路由度量接管，没有健康检查 |
| 保留配置 | 脚本发现已有 `network.lan` 就整段跳过，保留配置的 sysupgrade 不会再被打回 192.168.1.1 |
| 模组看门狗 | `modem-wan-watch` 每 60 s 读槽 1 卡状态；连续两次非 `present` → `ifdown wwan` + `AT+CFUN=1,1`（10 分钟节流）；卡恢复后 `ifup wwan` |
| 首启接口 | 新增 `zzz99-edge610-network-modem`：建 `network.wwan`（qmi、`apn cmnet`、`ipv4v6`、metric 100、auto）并把 `wwan` 加进 `wan` 防火墙 zone |

## 2026-11-11 SFP 口适配

| 项 | 结论 |
| --- | --- |
| 端口映射 | 插 SFP1 后只有 `05:00.1`（`eth3`）能读出模块 EEPROM → **SFP1 = `eth3`**，SFP2 = `eth2`（`05:00.0`） |
| 模块 | 电口 SFP：`OEM` / `OYJ-SFP-T` rev A，1.25G，序列号 `82608030053`（SFP1）/ `82608150004`（SFP2），日期 2026-11-04 |
| 链路 | 插线后 `ixgbe 0000:05:00.1 eth3: NIC Link is Up 1 Gbps, Flow Control: RX/TX`，全双工、`rx_errors`/`rx_crc_errors` 均为 0；`ip link set up` 后模块 PHY 需约 2 s 才起 link，此前会看到一次 `Up → Down` |
| 端口模式 | ixgbe 报 `Supported link modes: 1000baseKX/Full`——主机侧固定 1G SGMII 背板模式，10/100M 由模块自身 PHY 与对端协商 |
| DDM | 两个模块 A2 页逐字节相同（temp 19.8 °C、Vcc 3.31 V、Tx/Rx 固定值），电口无光路，属占位数据；A2 `0x0180` 往后全 0，模块未实现铜口寄存器映射 → 不可用于监控 |
| 默认网络 | `zzz99-edge610-network` 的 `br-lan` 端口表改为 `lan1..lan5` + `eth3` + `eth2`：两个 SFP 笼默认都是 LAN 口，插线即用；`lan6` 仍是 WAN |
| 模块信息 | 镜像装 `ethtool-full`（不是默认的 tiny 变体）：`ethtool -m eth3` 解码 A0 页（`Identifier`/`Vendor name`/`Vendor PN`/`Serial number`），tiny 变体带 `--disable-pretty-dump` 只会输出十六进制 |

## 2026-11-11 刷机实测：16M 启动分区装不下配置备份

在第一台真机上用 `sysupgrade` 刷本仓库镜像（保留配置）时发现：刷完重启后 **root 密码变成空**，SSH 被 dropbear 拒绝（`User 'root' has blank password, rejected`），LuCI 停在"设置密码"页；串口上能看到 `There is no root password defined on this device!`。网络配置本身正常恢复（`lan` 仍是 10.1.2.3、`gateway 10.1.2.1`、`br-lan` 端口表含 `eth2/eth3`）。

原因：sysupgrade 把配置备份写到 p1（`/boot`，vfat），镜像里该分区只有 **16 MB**，扣掉 kernel+grub 后剩 9.5 MB；而带 openclash 的备份实测 **10.5 MB**（`etc/openclash/core/clash_meta` 16 MB 与 `GeoSite.dat` 10 MB 被压缩后仍是大头）。备份写不下 → 恢复时 tar 只解开前半部分，`/etc/shadow` 排在后面，于是密码丢失；`/etc/config/*` 在前面所以恢复了。

修复：镜像种子配置加 `CONFIG_TARGET_KERNEL_PARTSIZE=64`（boot 分区 16→64 MB，可用空间约 57 MB）。代价是 rootfs 分区少 48 MB，但首启 `zzz98-edge610-resize` 会把它扩到整盘，实际无损失；已有设备升级时分区表变化会触发整盘写入（sysupgrade 自己处理）。

注意：升级前可先手动 `sysupgrade -b backup.tar.gz` 并把备份拷到别处，以免再遇到同类截断。

## 2026-11-11 开机 sh 报错：Intel 微码没装

现象：每次开机串口/控制台都会出现 `sh: write error: Invalid argument`。定位到 OpenWrt x86 的 `/lib/preinit/02_load_x86_ucode`：

```sh
if [ -e "/sys/devices/system/cpu/microcode/reload" ]; then
	echo 1 > /sys/devices/system/cpu/microcode/reload
fi
```

内核开了 `CONFIG_MICROCODE_LATE_LOADING=y` + `CONFIG_MICROCODE_LATE_FORCE_MINREV=y`，但镜像里没有 `/lib/firmware/intel-ucode/`，于是写入 `reload` 返回 `EINVAL`（手动复现 `rc=1`），busybox sh 把它报成上面那行错。副作用不只是报错：`dmesg` 显示 `Register File Data Sampling: Vulnerable: No microcode`，CPU 停在出厂修订 `0x0000002e`。

修复：镜像加 `CONFIG_PACKAGE_intel-microcode=y`（树内 `package/firmware/intel-microcode`，20251111，安装到 `/lib/firmware/intel-ucode/`）。preinit 的 reload 之后能正常加载，报错消失、RFDS 等漏洞由微码覆盖。

顺带把启动分区从 64 MB 提到 **128 MB**（`CONFIG_TARGET_KERNEL_PARTSIZE=128`，等于上游 armsr 默认档）：配置备份随着 openclash 规则增长还有余量。

## 2026-11-12 全新安装（`sysupgrade -n`）暴露的首启网络 bug

干净刷机后发现 `br-lan` 里只有 `eth0`、没有 `wan`：`zzz99-edge610-network` 用「`network.lan` 是否存在」判断"用户已经配置过"，可 board.d 的 `99-default_network` 在这之前就已经生成了 `lan=br-lan(eth0)`，于是脚本直接退出，六个 RJ45 口和两个 SFP 笼子全都没进桥（`eth0` 是 DSA conduit，把它当普通网卡桥接反而更糟）。

修复：改用"是否为出厂默认"判断——`lan.ipaddr` 不是 `192.168.1.1` 或设置了 `lan.gateway` 才算用户改过（并写 `/etc/edge610-network-applied` 标记，之后的升级直接跳过）；否则只改板子拥有的部分：替换 br-lan 的 ports 为 `lan1..lan5 + eth3 + eth2`、确保 `lan` 指向 `br-lan`、在缺 `wan` 时加 `wan=lan6(dhcp)`，其它包加的接口（`docker`、`wwan`）不动。

## 2026-11-12 出厂预置 root 密码

全新安装后 root 没有密码，dropbear 会拒绝空密码登录，必须接串口才能进系统。现在镜像里加 `zzz99-edge610-password`：只在 `/etc/shadow` 的 root 哈希为空时写入 `edge610pass` 的 sha256-crypt 值，保留配置升级（root 已有哈希）不会触发。用户登录后 `passwd` 改掉即可，脚本也不会再匹配。

### 修正：默认值判断漏掉了 `192.168.1.1/24`

第一版修复用 `[ "$ipaddr" != "192.168.1.1" ]` 判断"用户改过"，但 board.d 在新版 OpenWrt 里写的是 `list ipaddr '192.168.1.1/24'`，`uci get` 返回 `192.168.1.1/24`，于是出厂配置被误判成用户配置，脚本又直接退出（现象同前：`br-lan` 只有 `eth0`）。改成 `case` 同时接受 `192.168.1.1` 和 `192.168.1.1/24`。

另外 `PKG_RELEASE` 提到 2：OpenWrt 的包构建按目录 mtime 判定是否需要重装文件，新增的 `zzz99-edge610-password` 没进到已缓存的 apk 里，干净刷机后 root 仍然是空密码。

## 2026-11-12 开关模块找不到 P2SB BAR：ACPI 资源嵌到了 PCI 窗口下面

现象：某次开机后 `/sys/class/net` 只剩 `lo/docker0/wwan0`，6 个 RJ45 + 2 个 SFP 全没了；dmesg 报

```
edge610-switch: P2SB BAR unavailable (device hidden by BIOS and no iomem hint); pass p2sb_bar_addr=
insmod: failed to insert .../edge610_switch_standalone.ko
```

根因：模块只在 `iomem_resource.child`（第一层）里找名字含 `INTC3000`、大小 `0x10000`、`start - 0xc20000` 16MB 对齐的资源。这台机器这次启动时该资源挂在 PCI host bridge 窗口**下面一层**：

```
fdc20000-fdc2ffff : INTC3000:00          ← 实际在这里（depth 2）
```

于是扫描为空，模块 `return -ENODEV`，init 脚本随之中止，连 `ixgbe` 都没加载。

手工验证：`insmod edge610_switch_standalone.ko p2sb_bar_addr=0xfd000000` 立刻成功（`north window ... padbar=0x400`、`88E6190 rev 1`、`cpu10 link=up`），确认 BAR 值本身没变。

修复：`p2sb_bar_from_iomem()` 改为**递归**遍历资源树（两个模块同样修改），不再假设资源在第一层。
