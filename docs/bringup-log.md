# Edge 610 固件开发时间线（Bring-up Log）

记录从"交接文档"到"硬件端到端跑通"的完整过程、关键发现与证据，供后续维护参考。
时间均为 UTC，2026-11-07 / 11-08 两天。

---

## 阶段 0 — 交接文档（ImageBuilder 路线）

交接文档给出 GitHub Actions + OpenWrt **ImageBuilder** 方案（23.05.5），目标：
6×RJ45（Marvell DSA）+ 2×SFP（X553）、关闭硬件看门狗、内置 OpenClash + mihomo `amd64-v1`、
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
- 改为**路径无关**校验：manifest 断言包、`find build_dir -path '*/lib/modules/*'` 找模块、rootfs tar 里查文件/跑 `clash_meta`

## 阶段 4 — 插件与工具链完善

- run `42432099874`：全绿，产物 60.1MB
- 烤入中文 LuCI、`luci-app-ttyd`、`package-manager`、`statistics`、`ddns`、`sqm`、`wireguard`、诊断工具（ethtool/tcpdump/htop/mtr/iperf3/iftop/bind-host/nano/pciutils/usbutils/lm-sensors/block-mount）、USB 网卡/存储 kmod
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
（设备无 `base64`/`od`/`xxd`，但 OpenClash 依赖的 `ruby` 可用 `String#unpack1("m")` 解码），
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
`03:00.0`（`eth0`）是交换 conduit，`03:00.1`（`eth1`）空闲。固件不再预配 WAN，SFP 口留给用户自行分配。

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
