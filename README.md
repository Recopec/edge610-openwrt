# Edge 610 OpenWrt 固件自动构建

**简体中文** | [English](README.en.md)

为 **VMware SD-WAN Edge 610**（Dell EMC VEP1400 同款硬件）定制的 OpenWrt 镜像，GitHub Actions 一键全源码构建。

- 目标机：Intel Atom **C3308**（2C/2T 1.6GHz，无 AVX/AVX2）/ 4GB DDR4 / 16GB eMMC（`/dev/mmcblk0`，14.6GiB 可用）/ 无显示输出（Micro-USB 串口 115200 8N1）
- 网络：2× **1G SFP**（SoC 原生 X553，`ixgbe`）+ 6× **1G RJ45**（板载 Marvell 88E6190，DSA `lan1..lan6`）——全部端口上限 1G，见[速率上限](#速率上限重要)
- 看门狗：板载 PIC 硬件 WDT（iSMT SMBus `0x22/0x24`），开机由脚本清除，否则 4~5 分钟硬重启

## 界面预览

| 状态概览 |
| --- |
| ![状态概览](docs/screenshots/01-overview.png) |

| 网络接口 | 实时流量（千兆打满） |
| --- | --- |
| ![网络接口](docs/screenshots/02-network.png) | ![实时流量](docs/screenshots/04-realtime.png) |

| 挂载点（根分区已扩容） | Docker |
| --- | --- |
| ![挂载点](docs/screenshots/05-mounts.png) | ![Docker](docs/screenshots/06-docker.png) |

> 实机截图：Argon v3 主题 + 中文界面。该机 LAN 为 `10.1.2.3/24`，镜像默认 `192.168.1.1/24`。

## 实机照片

| 正面 | 背面 |
| --- | --- |
| ![正面](docs/hardware/front.jpg) | ![背面](docs/hardware/back.jpg) |

> 背面从左到右：MAIN/GPS 天线座、2× SFP（标注 1/2）、GE1/GE2、GE3/GE4、AUX；Micro-USB 串口在背板小铁片后。

## 硬件实测（本机）

| 项目 | 实测值 |
| --- | --- |
| CPU | `Intel(R) Atom(TM) CPU C3308 @ 1.60GHz`（2C/2T，无 AVX/AVX2） |
| 内存 | 4,003,672 kB ≈ 3.8 GiB |
| eMMC | `mmc0:0001 AJTD4R` 14.6 GiB（`/dev/mmcblk0`；HS400，实测顺序读 ~293 MB/s。镜像布局：p1 16M vfat `/boot`、p2 rootfs、p128 239K BIOS boot） |
| 网卡 | 4× `8086:15c3` X553 Backplane（BIOS 显示 Chip Type **X550**） |
| 网口映射 | `eth0` = `03:00.0` = 交换 CPU 链路（本机 **CPU port 10**，conduit）；`eth1` = `03:00.1` 未使用；`eth2` = `05:00.0`、`eth3` = `05:00.1` = 两个 SFP 口 |
| SFP 速率 | **只有 1G**（不支持 2.5G，也不支持 10G）。Dell 规格书：Edge 610 = `2×1G SFP`，620/640/680 才是 `2×10G SFP+`；四个 X553 全是 `8086:15c3` = `X550EM_A_KR_L`（1G 背板版），驱动对该 device ID 只返回 1G。实测强制 2.5GBASE-X（`x553_speed=2500` + 交换机 `MAC_CTL=0x303f`）链路仍锁定 1G |
| WiFi | `168c:003c` QCA986x/988x（ath10k + `ath10k-firmware-qca988x`） |

> 为什么不用 ImageBuilder：官方 x86 预编译内核关闭了 `CONFIG_NET_DSA` / `MV88E6XXX`，没有 `i2c-ismt`，也无法编译本机所需的外挂内核模块。因此本仓库改为 **全源码构建** OpenWrt 25.12.6。

## CPU 性能实测

C3308 没有 PassMark 条目（太冷门），用 **CoreMark 1.0** 实测（本机 OpenWrt 25.12.6，空闲系统）：

| 项目 | 实测值 |
| --- | --- |
| CoreMark 1.0（单线程） | **7,786.51** iterations/sec（110,000 次迭代，14.13 s，CRC 校验通过） |
| CoreMark 1.0（2 线程） | **14,582.09**（`-DMULTITHREAD=2 -DUSE_FORK=1`，扩展比 1.87×） |
| 每 MHz | 7,786 / 1600 ≈ **4.87 CoreMark/MHz**（Goldmont 乱序核） |
| 编译器 | GCC 14.3.0（OpenWrt 工具链），`-O2 -DPERFORMANCE_RUN=1 -lrt` |
| 对照（单线程） | Raspberry Pi 4 @1.5 GHz：8,257；RPi 3：3,800；i5-3320M：21,245；i3-10100：30,532 |
| 对照（PassMark） | 同系列 C3338：单核 1,028 / 多核 1,834（C3308 频率更低，同一档） |

OpenSSL 加解密（`openssl speed`，AES-NI 生效）：

| 算法 | 1 KB | 16 KB |
| --- | --- | --- |
| AES-128-CBC | 411 MB/s | 418 MB/s |
| AES-256-GCM | 403 MB/s | 547 MB/s |
| SHA-256 | 300 MB/s | 381 MB/s |
| ChaCha20-Poly1305 | 261 MB/s | 271 MB/s |

复现：

```bash
git clone --depth 1 https://github.com/eembc/coremark.git && cd coremark
make PORTABLE=1 PORT_DIR=linux \
  CC=<staging_dir>/toolchain-x86_64_gcc-14.3.0_musl/bin/x86_64-openwrt-linux-musl-gcc \
  ITERATIONS=100000
# 把 coremark.exe 拷到设备执行 ./coremark
```

## 其他板载硬件（实测）

| 硬件 | 状态 |
| --- | --- |
| **Sierra Wireless EM7565** LTE-A Cat-12 模组（USB `1199:9091`，SN `UF04360020011048`） | 镜像未带驱动；手动加载 `qmi_wwan` 后注册出 `wwan0` + `cdc-wdm0`。背板 MAIN/AUX = LTE 主/副天线，**GPS = GNSS 天线**。实测详见 [docs/lte.md](docs/lte.md) |
| **GPS/GNSS** | 即 EM7565 的定位功能（GPS/GLONASS/BeiDou），原厂用于 SD-WAN 设备定位；OpenWrt 下可经 QMI LOC 或 `AT!GPS` 读取，需接 GPS 天线 |
| **小区参数查询** | PCI/ECGI/TAC/邻区/信号/APN 的 AT 与 QMI 命令速查：[docs/lte-cell-info.md](docs/lte-cell-info.md) |
| **Intel QuickAssist (QAT)** `8086:19e2` | 加密/压缩协处理器；OpenWrt 无驱动（需 Intel 外挂 qat17），未启用 |
| **QCA988x WiFi 5** `168c:003c` | ath10k 正常；默认配置 `disabled '1'`，`wifi reload` 后 `phy0-ap0`（5GHz/80MHz/23dBm）可用 |
| **SD Host 控制器** `8086:19db` | 驱动板载 eMMC（HS400），无第二个 mmc 设备 |
| **SMBus 设备** | `0x22`/`0x24` = PIC（看门狗控制，开机写 0 关停）；`0x40` = 电源/遥测；`0x50–0x57` = EEPROM/FRU；`0x20/0x21` 等只写不读 |
| **温度** | coretemp 50–56 °C；8 个交换机端口传感器 55–57 °C |
| **ME (HECI)** `8086:19d3` | 存在，无用途 |

## 速率上限（重要）

| 接口 | 上限 | 依据 |
| --- | --- | --- |
| 6×RJ45 `lan1..lan6` | **1G/口** | Marvell 88E6190 是千兆交换机 |
| 2×SFP | **1G** | Dell 规格书 Edge 610 = `2×1G SFP`；X553 是 `8086:15c3`（KR_L，1G 背板版） |
| 内部 CPU 链路（交换机 ↔ X553） | **1G** | 硬件可配 2.5GBASE-X，实测强制后链路仍锁 1G |

- **不支持 2.5G**：SFP 驱动能力表只有 1G/10G；CPU 链路实测 2.5G 起不来（`x553_speed=2500` + `MAC_CTL=0x303f` 仍 1G）。
- **不支持 10G**：10G SFP+ 只在 Edge 620/640/680（4/8/16 核）上；610 的 X553 被 strap 成 KR_L（1G）。
- 想要 2.5G/10G：换 620 以上机型，或外接 USB 2.5G 网卡（镜像已含 `kmod-usb-net-rtl8152`）。

## 构建产物

Actions 运行成功后下载 artifact `Edge610-OpenWrt-Image`（zip 内）：

| 文件 | 说明 |
| --- | --- |
| `openwrt-x86-64-generic-ext4-combined-efi.img.gz` | **刷机用镜像**（EFI，根分区 1024MB，构建系统默认名） |
| `edge610-YYYYMMDD-HHMM.img.gz` | 同一镜像的**带时间戳副本**（GMT+8；CI 与本机构建都会生成） |
| `openwrt-x86-64.manifest` | 已安装软件包清单 |
| `sha256sums` | 校验和 |

## 一键构建

1. 打开 Actions → **Build Edge 610 OpenWrt Image** → *Run workflow*（main 分支）。
2. 全程约 3.5~4 小时（4 核 runner 全源码构建 + 工具链）。失败时自动上传 `build-log` artifact（含 `build.log` / `dl.log`）。

### 本地构建（推荐用于迭代）

CI 每次都是全新 runner，必须重编 rustc + 工具链（约 70% 时间）。本地/VM 有缓存，**首次约 75 分钟，之后改包通常 3~10 分钟出镜像**。

```bash
# 要求：Ubuntu 24.04 x86_64，≥8 核，≥16GB 内存，≥60GB 空闲磁盘（ext4）
PROXY=http://192.168.68.1:7897 ./scripts/build-local.sh
```

- `PROXY` 可选：GitHub / OpenWrt 源在部分网络下不稳定时填本机代理。
- 脚本与 CI 完全同源（同 feeds pin、同 `.config` 种子、同 ixgbe autoload 剥离、同结尾校验），幂等可重跑。
- 产物：`~/work/openwrt/bin/targets/x86/64/openwrt-x86-64-generic-ext4-combined-efi.img.gz`
- 已内置下载容错：`CURL_OPTIONS` 单文件 600s 上限 + 低速 60s 中断，下载失败自动重试 3 次。

## 镜像内容

| 组件 | 版本 / 说明 |
| --- | --- |
| OpenWrt | 25.12.6（x86_64，kernel 6.12.112） |
| LuCI | 官方 feed |
| OpenHsalc | 0.48.002（官方稳定 release tag） |
| Mihomo 内核 | v1.19.33 `linux-amd64-v1`（**无 AVX2**，预置于 `/etc/openhsalc/core/hsalc_meta`） |
| DNS | `dnsmasq-full`（替换默认 dnsmasq） |
| 交换 | `kmod-dsa` + `kmod-dsa-mv88e6xxx` + 本仓库 `edge610_dsa`（端口名 `lan1..lan6`） |
| 网卡 | `kmod-ixgbe`（**autoload 已剥离**，由 init 脚本按序加载） |
| 看门狗总线 | `kmod-i2c-ismt` + `i2c-tools` |
| 温度 | `kmod-hwmon-coretemp` + `lm-sensors`（Denverton 走 MSR，`/sys/class/thermal` 有 zone） |
| WiFi | `kmod-ath10k` + `ath10k-firmware-qca988x`（板上 QCA986x/988x，默认未配置接口） |
| 默认网络 | `br-lan` = `lan1..lan6`，静态 `192.168.1.1/24`；**不预置 WAN**（`eth2`/`eth3` 留空，由用户在 LuCI 里自行分配） |
| 根分区 | 镜像内 1 GiB；**首启自动扩容到整块 eMMC**（`sfdisk` + `partx` + `resize2fs`） |
| 主题 | **Argon v3**（`jerrykuku/luci-theme-argon`，master；v3 起配置页内置在主题包） |
| 预置插件（基础） | LuCI 中文、`ttyd`（Web 终端）、`package-manager`、`statistics`、`ddns`、`sqm`、`wireguard`、`firewall` |
| 安全/证书 | `acme`+`uhttpd`（Let's Encrypt HTTPS）、`banip`（爆破封禁）、`acl`（多用户权限） |
| 虚拟化 | `lxc`（LXC 容器） |
| 加速/组网 | `kmod-tcp-bbr`（BBR 拥塞控制）、`zerotier`（组网，GUI 走 iStore）、`luci-app-wifischedule`（无线定时） |
| 对时/测速/流量 | `chrony`（精准对时）、`librespeed`（内网测速，可验证千兆线速）、`vnstat2`（流量历史） |
| 网络 | `mwan3`（多 WAN，配合双 SFP）、`pbr`（策略路由）、`upnp`、`nlbwmon`（流量统计）、`wol`、`udpxy`（IPTV 组播转单播）、`omcproxy`、`watchcat`（断网自愈）、`lldpd` |
| DNS/去广告 | **不预置**（按需 `apk add luci-app-adguardhome` / `luci-app-smartdns` / `luci-app-adblock-fast`） |
| 存储/共享 | `ksmbd`（SMB）、`hd-idle`、`filebrowser`（aria2/transmission 按需 `apk add`） |
| 磁盘/文件系统 | `kmod-fs-exfat` / `vfat` / `ntfs3`、`kmod-usb-printer`、`e2fsprogs`、`smartmontools`、`hdparm` |
| 运维 | `commands`、`irqbalance`、`p910nd`（USB 打印）、`ser2net`、`filemanager` |
| VPN/穿透 | 仅内核+协议（`kmod-wireguard`、`wireguard-tools`、`luci-proto-wireguard`）；openvpn/tailscale/frpc 按需 `apk add` |
| 容器 | **内置 docker**：`dockerd`/`containerd`/`runc`/`tini`/`docker` CLI/`docker-compose` + `luci-app-dockerman`（内核依赖 veth/ipt-nat/ipt-physdev/nf-ipvs 一并内置） |
| 诊断工具 | `ethtool` `tcpdump` `htop` `mtr` `iperf3` `iftop` `bind-host`(dig) `nano` `pciutils`(lspci) `usbutils`(lsusb) `lm-sensors` `block-mount` |
| USB 扩展 | `kmod-usb-net-rtl8152` / `asix-ax88179` / `cdc-ether`（USB 网卡或手机共享作 WAN）、`kmod-usb-storage`、`kmod-fs-ext4` |

## 仓库结构

```
.github/workflows/build.yml       全源码构建流水线（14 步，含断言与镜像校验）
patches/openwrt/0001-image-mkfs-ext4-use-mke2fs.patch  rootfs 改用 mke2fs（在线扩容）
package/edge610-board/
├── Makefile                      三个内核包 + 板级包定义
├── src/
│   ├── edge610_switch_standalone.c   ixgbe 加载前初始化 X553/交换芯片
│   ├── edge610_dsa.c                 注册 88E6190 DSA（端口 lan1..lan6）
│   └── Makefile
└── files/
    ├── etc/init.d/edge610           看门狗关闭 + 有序探测（standalone → ixgbe → DSA）
    ├── etc/modprobe.d/edge610.conf  板级模块参数
    ├── etc/uci-defaults/zzz99-edge610-network  首启网络配置（仅 LAN，无 WAN）
    └── etc/openhsalc/core/          hsalc_meta 由 CI 下载（已 gitignore）
```

### 关键设计

- **加载顺序**：`ixgbe` 的 autoload 在构建时被删除，`/etc/init.d/edge610`（START=19，早于 network）依次执行：
  `insmod edge610_switch_standalone cpu_port=0 x553_sgmii=1 cpu_mac_ctl=0x203e serdes_autoneg=1` → `modprobe ixgbe` → `modprobe mv88e6xxx` → `insmod edge610_dsa conduit_name=<ethX> force_cpu_phyctl=0x203e`。
  （busybox 的 `modprobe` 会静默丢弃 `name=value`，所以板级模块用 `insmod` 传参。）
- **conduit 检测**：优先 PCI `0000:03:00.0` 的 netdev；回退取 ixgbe 中 MAC 最小的网口（conduit 是四个连续 X553 MAC 的第一个）。conduit 口只置 up，不配地址。
- **看门狗**：扫描 `/sys/bus/i2c/devices/*/name` 中的 `iSMT` 适配器，向 `0x22`/`0x24` 写 `0x00`；失败仅记录日志，不阻塞启动。
- **端口改名**：`edge610_dsa` 中端口名由上游 `ge1..ge6` 改为 `lan1..lan6`，与 OpenWrt DSA 惯例及网络默认配置一致。
- **根分区**：`CONFIG_TARGET_ROOTFS_PARTSIZE=1024`（默认 104MB 装不下 mihomo + ruby 等），首启由 `zzz98-edge610-resize` 在线扩到整盘。
  前提是镜像用 `mkfs.ext4` 而不是 OpenWrt 默认的 `make_ext4fs` 生成：后者的 resize inode 布局会让内核在线扩容报
  `reserve_backup_gdb: reserved block 64 not at offset 63`（[openwrt#7729](https://github.com/openwrt/openwrt/issues/7729)）。
  本仓库用 `patches/openwrt/0001-image-mkfs-ext4-use-mke2fs.patch` 替换 `Image/mkfs/ext4`（在 fakeroot 里 `chown -R 0:0`，保证镜像内属主为 root）。

## 只装板级包（不刷机）

如果机器上已经跑着 **OpenWrt 25.12.6 / kernel 6.12.112**，可以只装板级包，不必刷整镜像。

构建（在 OpenWrt 源码树里，已含本仓库的 `package/edge610-board`）：

```sh
make package/edge610-board/compile V=s
```

产物：

| 文件 | 说明 |
| --- | --- |
| `bin/packages/x86_64/base/edge610-board-*.apk` | 板级包：init 脚本 + modprobe 参数 + 首启网络 + mihomo 内核（约 25 MB） |
| `bin/targets/x86/64/packages/kmod-edge610-switch-*.apk` | 交换芯片初始化模块 |
| `bin/targets/x86/64/packages/kmod-edge610-dsa-*.apk` | DSA 注册模块 |
| `bin/targets/x86/64/packages/kmod-i2c-ismt-*.apk` | 看门狗总线驱动 |

安装：

```sh
apk add --allow-untrusted ./kmod-i2c-ismt-*.apk ./kmod-edge610-switch-*.apk \
    ./kmod-edge610-dsa-*.apk ./edge610-board-*.apk
/etc/init.d/edge610 enable
reboot
```

注意：

- **kmod 与内核版本严格绑定**（`6.12.112`），内核不一致会加载失败。
- 官方镜像里 `ixgbe` 开机自动加载，会抢在 `/etc/init.d/edge610` 之前 probe，X553 的 SGMII 模式来不及设置。
  只用包的话需要先删掉 ixgbe 的 autoload（`/etc/modules.d/` 中与 ixgbe 相关的文件），由 init 脚本按序加载；否则请直接用整镜像。

## 刷机

> 必须用本仓库构建的镜像（已打 mke2fs 补丁）。用 OpenWrt 默认 `make_ext4fs` 生成的镜像，
> 首启在线扩容会失败（openwrt/openwrt#7729）。

1. 准备 U 盘：一个 OpenWrt 启动盘 + 一个 exfat 数据分区，把 `edge610-*.img.gz` 放进数据分区。
2. 拆背板小铁片露出 Micro-USB 串口（CP210x），PuTTY：`115200 8N1`、无流控。
3. 插 U 盘开机，F12 选 USB 启动，进入 OpenWrt 后：

   ```sh
   lsblk                                   # 确认 /dev/mmcblk0 为 eMMC
   mkdir -p /mnt/usb && mount /dev/sdbX /mnt/usb
   gzip -dc /mnt/usb/edge610-*.img.gz | dd of=/dev/mmcblk0 bs=4M conv=fsync
   sync
   ```

4. 拔 U 盘，`reboot`。首启 `zzz98-edge610-resize` 自动把根分区扩到整盘，
   `df -h /` 应为 ~14.3G（日志：`logread -e edge610-resize`）。

## 开机验收

串口执行：

```sh
ip link                     # 应出现 lan1..lan6（+ lo 与若干 ethX）
logread -e edge610          # 看门狗清除、conduit、端口 up 日志
df -h /                     # 从 eMMC 启动应为 ~14.3G（首启扩容生效）
sensors                     # 应看到 Core 0/Core 1 温度（kmod-hwmon-coretemp）
/etc/openhsalc/core/hsalc_meta -v   # 必须回显 Mihomo Meta ... linux amd64（amd64-v1）
```

- 空闲运行 ≥10 分钟不重启 → 看门狗关闭生效。
- 网线接 **LAN1**，浏览器打开 `http://192.168.1.1` → LuCI。
- 服务 → OpenHsalc：载入订阅配置，启动代理。

## 实现历程与关键发现

完整的调试时间线（含证据、串口日志、构建耗时）见 [`docs/bringup-log.md`](docs/bringup-log.md)。

这台机器踩过的构建期坑，维护时值得记住：

| 坑 | 现象 | 处理 |
| --- | --- | --- |
| BIOS 隐藏 P2SB（`8086:19dd` 不在 `lspci`） | 模块静默 `-ENODEV`，`ixgbe` 不加载，只有 `lo` | 模块从 `/proc/iomem` 的 `INTC3000:00` 反推 BAR（本机 `0xFD000000`）；可参数 `p2sb_bar_addr=` 覆盖 |
| uci section 名不允许 `-` | `uci: Parse error (invalid character in name field)`，网桥不生效 | `config device` 匿名 + `option name 'br-lan'`（构建期已有断言） |
| `make download` 无总超时 | 半死连接无限挂起，构建看似"卡住" | `CURL_OPTIONS=--max-time 600 --speed-time 60 --speed-limit 1024` + 重试 |

## 故障排查

| 现象 | 处理 |
| --- | --- |
| `ip link` 无 `lan1..lan6` | `logread -e edge610` 看 `edge610_switch_standalone` / `edge610_dsa` 报错；`dmesg \| grep -i -E 'dsa\|mv88e'`；`lsmod \| grep -E 'edge610\|mv88e\|dsa'` |
| 日志 `P2SB BAR unavailable` | 该机 BIOS 隐藏了 P2SB（`8086:19dd` 不在 `lspci` 里）。模块会从 `/proc/iomem` 的 `INTC3000:00` 反推 BAR（通常 `0xfd000000`）；仍失败时手动指定：`modprobe edge610_switch_standalone p2sb_bar_addr=0xfd000000 ...` 和 `modprobe edge610_dsa conduit_name=ethX p2sb_bar_addr=0xfd000000` |
| 4~5 分钟自动重启 | 看门狗未关：`logread -e edge610` 应无 `iSMT SMBus adapter not found`。手动确认：`modprobe i2c-ismt; grep . /sys/bus/i2c/devices/*/name`，然后 `i2cset -y <bus> 0x22 0 0 b` |
| Mihomo 报 `Illegal instruction` | 核被替换成了 v2/v3（AVX）。只可用 `linux-amd64-v1`，重新放回 `/etc/openhsalc/core/hsalc_meta` |
| 没有 WAN | 默认不预置 WAN：`br-lan` 只含 `lan1..lan6`，`eth2`/`eth3`（SFP）保持未配置。需要 WAN 时在 LuCI「网络→接口→添加」里自己建，设备可选 `lan1..lan6` 或 `eth2/eth3`（`logread -e edge610` 里的 `conduit:` 是交换 uplink，**不要**配地址） |
| eth 口数量不止 eth0/eth1 | X553 共 4 个 MAC，枚举数量随 BIOS 变化；以日志中 `conduit:` 行与实际插线为准 |

## 修改与重建

- 改镜像内容：编辑 `package/edge610-board/` 或 workflow 中的 `.config` 种子 → commit 推送 → Actions 重跑。
- `.config` 种子中的关键包在构建时会被断言（defconfig 后 grep 校验），缺失即失败，避免“构建成功但内容不对”。
- 构建末尾会校验：镜像存在且大小合理、manifest 含关键包、rootfs 内含模块与脚本、`hsalc_meta` 可执行且回显 Mihomo。
