# Edge 610 OpenWrt 固件自动构建

**简体中文** | [English](README.en.md)

为 **VMware SD-WAN Edge 610**（Dell EMC VEP1400 同款硬件）定制的 OpenWrt 镜像，GitHub Actions 一键全源码构建。

- 目标机：Intel Atom **C3308**（2C/2T 1.6GHz，无 AVX/AVX2）/ 4GB DDR4 / 16GB eMMC（`/dev/mmcblk0`，14.6GiB 可用）/ 无显示输出（Micro-USB 串口 115200 8N1）
- 网络：2× **1G SFP**（SoC 原生 X553，`ixgbe`）+ 6× **1G RJ45**（板载 Marvell 88E6190，DSA `lan1..lan6`）——全部端口上限 1G，见[速率上限](#速率上限重要)
- 看门狗：板载 PIC 硬件 WDT（iSMT SMBus `0x22/0x24`），开机由脚本清除，否则 4~5 分钟硬重启

## 目录

- [界面预览](#界面预览)
  - [4G/LTE 模组（EM7565）](#4glte-模组em7565)
- [实机照片](#实机照片)
- [硬件实测（本机）](#硬件实测本机)
- [CPU 性能实测](#cpu-性能实测)
- [其他板载硬件（实测）](#其他板载硬件实测)
- [速率上限（重要）](#速率上限重要)
  - [SFP 口实测](#sfp-口实测)
- [构建产物](#构建产物)
- [一键构建](#一键构建)
  - [本地构建（推荐用于迭代）](#本地构建推荐用于迭代)
- [镜像内容](#镜像内容)
- [仓库结构](#仓库结构)
  - [关键设计](#关键设计)
- [只装板级包（不刷机）](#只装板级包不刷机)
- [刷机](#刷机)
  - [从 U 盘一键装到 eMMC](#从-u-盘一键装到-emmc)
  - [备用的 dd 路径](#备用的-dd-路径)
  - [首启脚本顺序](#首启脚本顺序)
- [升级](#升级)
- [串口控制台](#串口控制台)
- [开机验收](#开机验收)
- [实现历程与关键发现](#实现历程与关键发现)
- [故障排查](#故障排查)
- [修改与重建](#修改与重建)
- [已知限制](#已知限制)
- [版本与发布](#版本与发布)

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

> 实机截图：Argon v3 主题 + 中文界面。**截图时**该机 LAN 是 `10.1.2.3/24`（旁路由部署）；镜像默认 `192.168.1.1/24`。

### 4G/LTE 模组（EM7565）

状态 → **Modem** 下有五个页签，全部由本仓库的 `edge610-board` 包提供，不依赖额外插件：

| 页签 | 内容 |
| --- | --- |
| 状态 | 首屏直接给结论：链路（运营商 / 制式 / 频段 / 附着）、信号（RSRP 主值 + SINR/RSRQ + 近 60 次采样折线）、实时上下行与累计流量；下面是服务小区、连接与注册、信号条、数据连接、硬件、邻区（同频 / 异频）、模组状态 |
| 设置 | SIM 槽（`AT!UIMS`）、制式（`AT!SELRAT`）、扫描 / 自动选网、APN 与鉴权、频段锁（`AT!BAND`，改动即重拨）；右上角**复位模组**（`AT+CFUN=1,1`） |
| GPS | 启动/停止定位、经纬度与首次定位耗时（TTFF）、可见卫星（仰角 / 方位 / SNR）、`AT!GPSSTATUS?;!GPSLOC?;!GPSSATINFO?` 原始输出 |
| 短信 | 发送、收件箱（按条删除）、已发送（单条删除 / 清空） |
| AT | 原始 AT 调试：快捷命令、超时、`;` 串联、输出复制 |

| 状态（首屏即结论） |
| --- |
| ![模组状态](docs/screenshots/07-modem-status.jpg) |

| 设置 | GPS |
| --- | --- |
| ![模组设置](docs/screenshots/08-modem-settings.jpg) | ![GPS](docs/screenshots/09-modem-gps.jpg) |

| 短信 | AT |
| --- | --- |
| ![短信](docs/screenshots/10-modem-sms.jpg) | ![AT 调试](docs/screenshots/11-modem-at.jpg) |

页面之外，镜像还带这些：

- **首启建接口**：`zzz99-edge610-network-modem` 创建 `network.wwan`（qmi / `/dev/cdc-wdm0` / `apn cmnet` / `pdptype ipv4v6` / `metric 100`）并加入防火墙 `wan` zone；已有 `lan` 配置时不重写 `/etc/config/network`。
- **出口顺序**：有线 `lan6`（WAN，DHCP）优先，LTE 是 mwan3 的 failover 成员（member metric 2）；mwan3 默认启用，IPv4 规则（`default_rule_v4` / `https`）走 `failover` 策略，探测 30 s 一次，故障切换约 1.5 分钟。IPv6 不由 mwan3 管理，走 netifd 的默认路由。
- **`modem-at`**：自动探测 AT 口（option 驱动的序号随 USB 组合变化，可能是 `ttyUSB1` 或 `ttyUSB2`），用 `flock` 与页面轮询互斥。
- **`modem-wan-watch`**：30 s 循环。SIM 每 60 s 用 QMI 查一次槽 1，连续两次非 `present` → `ifdown wwan` + `AT+CFUN=1,1`（10 分钟节流），卡可读且 `auto=1` → `ifup`；同时比对 `AT+CGPADDR` 与 `wwan0` 地址，PDP 地址漂移就重拨（退避 120→900 s）。
- **速率的口径**：QMI WDS 只给会话参数（IP / 网关 / DNS / MTU），没有“协商速率”这种字段；空口能力看 `AT!GSTATUS?`（频段 / 带宽 / CA），实际吞吐看 `wwan0` 计数差分——首屏的“下行 / 上行”是相邻两次轮询的平均值，刷新间隔越大越平滑。

已知限制：

- **换卡必须复位**：SIM 检测线被 `AT!CUSTOM="SIMHOTSWAPDIS",1` 屏蔽，热插拔后模组不会自己重新初始化；拔插后点一次「复位模组」，实测约 50 s 恢复注册与拨号。
- **只能插上槽**：`AT!UIMS=0` 落在已接线的槽 1，`AT!UIMS=1` 是未接线的槽 2，`AT!UIMS=2` 该固件直接回 `ERROR`。
- **AT 页没有命令白名单**：有 LuCI 权限即可发 `AT!RESET`、`AT!USBCOMP` 等，改错会丢 AT 口。串联时个别查询（如 `AT!SELRAT?`）会回 `Unknown RAT mode`，需单独发送。

> 模组截图中的 IMEI / IMSI / ICCID / 本机号码 / 短信验证码 / 坐标已打码。

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
| eMMC | `mmc0:0001 AJTD4R` 14.6 GiB（`/dev/mmcblk0`；HS400，实测顺序读 ~293 MB/s。镜像布局：p1 **128M** vfat `/boot`、p2 rootfs、p128 239K BIOS boot。p1 要放 keep-config 升级的配置备份，16M 装不下带 openclash 的备份） |
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
| **Sierra Wireless EM7565** LTE-A Cat-12 模组（USB `1199:9091`，SN `UF04360020011048`） | 自 `ec39bbf` 起镜像内置：option 驱动提供 AT 口，`qmi_wwan` 提供 `wwan0` + `cdc-wdm0`。背板 MAIN/AUX = LTE 主/副天线，**GPS = GNSS 天线**。实测详见 [docs/lte.md](docs/lte.md) |
| **GPS/GNSS** | 即 EM7565 的定位功能（GPS/GLONASS/BeiDou/Galileo/QZSS），原厂用于 SD-WAN 设备定位；OpenWrt 下可经 QMI LOC 或 `AT!GPS` 读取，需接 GPS 天线 |
| **小区参数查询** | PCI/ECGI/TAC/邻区/信号/APN 的 AT 与 QMI 命令速查：[docs/lte-cell-info.md](docs/lte-cell-info.md) · [全部 AT 命令](docs/lte-at-commands.md) |
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

### SFP 口实测

| 项 | 结论 |
|---|---|
| 端口映射 | 插模块后只有对应 netdev 能读出 EEPROM → **SFP1 = `eth3`（`05:00.1`）**，SFP2 = `eth2`（`05:00.0`） |
| 默认配置 | 两个笼子都是 `br-lan` 成员（`lan1..lan5` + `eth3` + `eth2`），插线即用；`lan6` 为 WAN |
| 模块 | 电口 SFP `OYJ-SFP-T`（OEM，1.25G，SN `82608030053` / `82608150004`，2026-11-04） |
| 链路 | SFP1 接 1G 对端：`NIC Link is Up 1 Gbps, Flow Control: RX/TX`，全双工，`rx_errors`/`rx_crc_errors` = 0 |
| 起链时序 | `ip link set up` 后模块 PHY 约 2 s 才起链，之前会看到一次 `Up → Down`；空槽时是 `NO-CARRIER` |
| 速率协商 | 主机侧固定 1G SGMII/背板（`Supported link modes: 1000baseKX`），10/100M 由模块自身 PHY 与对端协商 |
| DDM | 电口模块 A2 页是占位值（两个不同序列号逐字节相同、无光路仍报 Rx 功率），A2 `0x0180` 之后全 0 → 不能用于监控 |
| 热插拔 | 模块插入即被识别（EEPROM 可读），不需要额外驱动；端口是常驻桥成员 |

**为什么 610 上不了 2.5G/10G**：

- 本板 4 个口全是 `8086:15c3` = `X550EM_A_KR_L`；`ixgbe` 的 `ixgbe_get_link_capabilities_X550em()` 对 `phy.type == x550em_kr` + `device_id == KR_L` **直接返回 1G**。
- 2.5G 只有在该端口 NVM strap `IXGBE_NW_MNG_IF_SEL`（CSR `0x11178`）的 `PHY_SPEED_2_5G`(bit20) 置位时才给——本板未置位，且这不是插模块能改的。
- 10G 需要 `X550EM_A_SFP`(`15ce`)/`SFP_N`(`15c4`)/`KR`(`15c2`) 这类 SKU；`allow_unsupported_sfp=1` 也无效，因为 KR_L 走 `x550em_kr` 分支，从不调用 SFP 白名单路径。

| 机型 | SFP 口 | X553 配置 |
|---|---|---|
| Edge 610 | 2× **1G SFP** | KR_L（`15c3`） |
| Edge 620 / 640 / 680 | 2× **1G/10G SFP+** | SFP / SFP_N（`15ce` / `15c4`） |

> Edge 600 系列只有 610/620/640/680（另有 610C/610N/620C/620N/640N），**没有 630**。



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
| Mihomo 内核 | v1.19.33 `linux-amd64-v1`（**无 AVX2**，预置于 `/etc/openclash/core/clash_meta`） |
| DNS | `dnsmasq-full`（替换默认 dnsmasq） |
| 交换 | `kmod-dsa` + `kmod-dsa-mv88e6xxx` + 本仓库 `edge610_dsa`（端口名 `lan1..lan6`） |
| 网卡 | `kmod-ixgbe`（**autoload 已剥离**，由 init 脚本按序加载） |
| 看门狗总线 | `kmod-i2c-ismt` + `i2c-tools` |
| 温度 | `kmod-hwmon-coretemp` + `lm-sensors`（Denverton 走 MSR，`/sys/class/thermal` 有 zone） |
| CPU 微码 | `intel-microcode`（20251111；内核 `CONFIG_MICROCODE_LATE_LOADING`，preinit 写入 `/sys/devices/system/cpu/microcode/reload`。不装会报 `sh: write error: Invalid argument`，且 CPU 停在出厂修订、对应 RFDS 等漏洞） |
| WiFi | `kmod-ath10k` + `ath10k-firmware-qca988x`（板上 QCA986x/988x，默认未配置接口） |
| 默认网络 | `br-lan` = `lan1..lan5` + `eth3`/`eth2`（两个 SFP 笼），静态 `192.168.1.1/24`；**`lan6` 作 WAN**（DHCP 客户端，metric 0） |
| 根分区 | 镜像内 1 GiB；**首启自动扩容到整块 eMMC**（`sfdisk` + `partx` + `resize2fs`） |
| 默认密码 | 全新安装的 root 密码预置为 `edge610pass`（`zzz99-edge610-password` 只在 `/etc/shadow` 里 root 为空时写入；保留配置升级不会覆盖用户改过的密码）。**首次登录后请改掉** |
| 主题 | **Argon v3**（`jerrykuku/luci-theme-argon`，master；v3 起配置页内置在主题包） |
| 预置插件（基础） | LuCI 中文、`ttyd`（Web 终端）、`package-manager`、`statistics`、`ddns`、`sqm`、`wireguard`、`firewall` |
| 安全/证书 | `acme`+`uhttpd`（Let's Encrypt HTTPS）、`banip`（爆破封禁）、`acl`（多用户权限） |
| 虚拟化 | `lxc`（LXC 容器） |
| 加速/组网 | `kmod-tcp-bbr`（BBR 拥塞控制）、`zerotier`（组网，GUI 走 iStore）、`luci-app-wifischedule`（无线定时） |
| 对时/测速/流量 | `chrony`（精准对时）、`librespeed`（内网测速，可验证千兆线速）、`vnstat2`（流量历史） |
| 网络 | `mwan3`（多 WAN：lan6 → LTE 故障切换，含探测与策略）、`pbr`（策略路由）、`upnp`、`nlbwmon`（流量统计）、`wol`、`udpxy`（IPTV 组播转单播）、`omcproxy`、`lldpd` |
| DNS/去广告 | **不预置**（按需 `apk add luci-app-adguardhome` / `luci-app-smartdns` / `luci-app-adblock-fast`） |
| 存储/共享 | `ksmbd`（SMB）、`hd-idle`、`filebrowser`（aria2/transmission 按需 `apk add`） |
| 磁盘/文件系统 | `kmod-fs-exfat` / `vfat` / `ntfs3`、`kmod-usb-printer`、`e2fsprogs`、`smartmontools`、`hdparm` |
| 运维 | `commands`、`irqbalance`、`p910nd`（USB 打印）、`ser2net`、`filemanager` |
| VPN/穿透 | 仅内核+协议（`kmod-wireguard`、`wireguard-tools`、`luci-proto-wireguard`）；openvpn/tailscale/frpc 按需 `apk add` |
| 容器 | **内置 docker**：`dockerd`/`containerd`/`runc`/`tini`/`docker` CLI/`docker-compose` + `luci-app-dockerman`（内核依赖 veth/ipt-nat/ipt-physdev/nf-ipvs 一并内置） |
| 诊断工具 | `ethtool`(full，`-m` 可解码 SFP EEPROM) `tcpdump` `htop` `mtr` `iperf3` `iftop` `bind-host`(dig) `nano` `pciutils`(lspci) `usbutils`(lsusb) `lm-sensors` `block-mount` |
| USB 扩展 | `kmod-usb-net-rtl8152` / `asix-ax88179` / `cdc-ether`（USB 网卡或手机共享作 WAN）、`kmod-usb-storage`、`kmod-fs-ext4` |

## 仓库结构

```
.github/workflows/build.yml      全源码构建流水线（workflow_dispatch 手动触发，14 步含断言与镜像校验）
patches/openwrt/
├── 0001-image-mkfs-ext4-use-mke2fs.patch   rootfs 改用 mke2fs（否则在线扩容失败）
├── 0002-usb-serial-option-add-em7565.patch option 只认 AT 接口，把 QMI 接口留给 qmi_wwan
├── 0003-image-guid-salt.patch              GPT UUID 混入提交号，不同版本镜像不再撞 UUID
└── 0004-grub-search-by-fs-uuid.patch       grub 按 boot 分区的文件系统 UUID 找内核（不按 label）
package/edge610-board/
├── Makefile                      三个内核包 + 板级包定义
├── src/
│   ├── edge610_switch_standalone.c   ixgbe 加载前初始化 X553/交换芯片
│   ├── edge610_dsa.c                 注册 88E6190 DSA（端口 lan1..lan6）
│   └── Makefile
└── files/
    ├── etc/init.d/edge610            看门狗关闭 + 有序探测（standalone → ixgbe → DSA）
    ├── etc/modprobe.d/edge610.conf   板级模块参数
    ├── etc/uci-defaults/zzz98-edge610-resize          直接 dd 镜像后首启扩 rootfs
    ├── etc/uci-defaults/zzz99-edge610-network         首启网络（lan1..lan5 为 LAN，lan6 为 WAN）
    ├── etc/uci-defaults/zzz99-edge610-network-modem   首启建 network.wwan 并加进 wan zone
    ├── etc/uci-defaults/zzz99-edge610-mwan3           首启给 mwan3 加 wwan 成员与 failover 策略
    ├── etc/uci-defaults/zzz99-edge610-password        首启预置 root 密码（仅在密码为空时）
    ├── usr/sbin/edge610-install      把当前系统克隆到 eMMC（分区表 + 扩容 + UUID + grub.cfg）
    ├── usr/bin/modem-at              AT 口自动探测 + flock 互斥
    ├── usr/bin/modem-sms-send        PDU 模式发短信
    ├── usr/bin/modem-wan-watch       SIM 掉卡 / PDP 地址漂移看门狗
    ├── usr/bin/verify-device         镜像内只读自检（模块、脚本、页面）
    ├── usr/lib/lua/luci/controller/modem.lua   模组页面后端（AT/QMI 采集）
    ├── usr/lib/lua/luci/view/modem/            状态 / 设置 / GPS / 短信 / AT 五个页面
    └── etc/openhsalc/core/           hsalc_meta 由 CI 下载（已 gitignore）
scripts/
├── build-local.sh                 本机构建（与 CI 同源，增量，首次约 75 分钟）
├── serial-console.py             串口控制台客户端（可走 HTTP 代理 CONNECT，便于跨网段）
├── serial-bridge.ps1              把 Windows 串口桥成 TCP :7001，远程驱动串口控制台
├── usb-prep.sh                    给 U 盘重新生成 p2 PARTUUID（两盘同镜像时用）
└── verify-device.sh               对已启动设备跑一遍验收（与镜像内的 verify-device 同源）
docs/                              实测记录：lte / lte-cell-info / lte-at-commands / bringup-log、截图
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

### 从 U 盘一键装到 eMMC

U 盘里的系统带 `edge610-install`（`/usr/sbin/`），**不带参数就是"把当前系统克隆到 eMMC"**：

```sh
edge610-install          # 提示输入 YES，然后克隆 + 扩容 + 换 UUID
edge610-install --yes    # 免确认
```

流程：确认目标是 `/dev/mmcblk0` 且不是正在运行的盘 → 尝试把 `/` 挂成只读并整盘克隆当前 U 盘（overlayfs 下只读挂载会失败，此时靠随后的 `e2fsck` 兜底）→ **按镜像布局重写目标盘的分区表**（512..262655 boot、262656..盘尾 rootfs，磁盘与分区 GUID 重新生成；克隆带来的表描述的是 U 盘大小，放到更小的 eMMC 上内核会直接拒绝）→ `e2fsck` + 把 rootfs 扩到整块 eMMC → 改 `grub.cfg` 的 `root=PARTUUID` 指向新根分区 → 提示关机拔盘、从 eMMC 启动。

> 安装后的 eMMC 只有 **p1（128 M boot）＋ p2（rootfs）** 两个分区，不像镜像那样带 p128。这不是省的：GRUB 的 `core.img` 是按"boot 文件系统在 gpt1"编的，`sfdisk` 按起始扇区编号，只有让 FAT 落在 512 才是 p1；`core.img` 本体仍留在 34..511 的空隙里，`boot.img` 按绝对扇区加载它，不经过分区表。实测这张表可以无人干预启动。
> boot 分区的 FAT 序列号也**故意不动**：GRUB 把它作为二进制搜索提示编进了 `core.img`，改了就得去改压缩过的二进制，提示对不上会停在裸 `grub>` 提示符（踩过）。两盘同时在场时的冲突用 `scripts/usb-prep.sh` 处理。

也可以直接写镜像文件（适合脚本化）：`edge610-install --yes /path/edge610-*.img.gz`，同样会扩容和换 UUID。

扩容不再依赖首启脚本（安装时就地完成）；`zzz98-edge610-resize` 仍保留，用于"直接 dd 镜像到 eMMC"的老路径——它按 `/dev/mmcblk0p2` + sysfs 定位，与 `PARTUUID` 无关，并且从 U 盘启动时会主动跳过。


> 走 `edge610-install` 装的 eMMC 有自己的 `rootfs PARTUUID`，和 U 盘不会撞。会撞的是**同一份镜像被 dd 到两块盘**：分区 UUID 和 FAT 序列号都一样，GRUB 的搜索可能认错盘，看起来像"从 U 盘启动却进了旧系统"；这种自测场景用 `scripts/usb-prep.sh /dev/sdX` 重新给 U 盘的 p2 生成 UUID 即可（详见[故障排查](#故障排查)）。

> 必须用本仓库构建的镜像（已打 mke2fs 补丁）。用 OpenWrt 默认 `make_ext4fs` 生成的镜像，
> 首启在线扩容会失败（openwrt/openwrt#7729）。

### 备用的 dd 路径

1. 准备 U 盘：一个 OpenWrt 启动盘 + 一个 exfat 数据分区，把 `edge610-*.img.gz` 放进数据分区。
2. 拆背板小铁片露出 Micro-USB 串口（CP210x），PuTTY：`115200 8N1`、无流控。
3. 插 U 盘开机（固件默认优先 U 盘；没选中就 F12 手动选），进入 OpenWrt 后：

   ```sh
   lsblk                                   # 确认 /dev/mmcblk0 为 eMMC
   mkdir -p /mnt/usb && mount /dev/sdbX /mnt/usb
   gzip -dc /mnt/usb/edge610-*.img.gz | dd of=/dev/mmcblk0 bs=4M conv=fsync
   sync
   ```

4. 拔 U 盘，`reboot`。首启 `zzz98-edge610-resize` 自动把根分区扩到整盘，
   `df -h /` 应为 ~14.3G（日志：`logread -e edge610-resize`）。

### 首启脚本顺序

`/etc/uci-defaults` 里的脚本按文件名排序执行，跑完自删。本仓库的五个都在 `zzz*` 段，所以包的初始化脚本（`10-fstab`、`60_luci-mwan3` …）先于它们：

| 顺序 | 脚本 | 作用 |
| --- | --- | --- |
| 1 | `zzz98-edge610-resize` | 把 `p2` 扩到整盘；`/` 不在 `mmcblk0p2` 上（从 U 盘启动）时主动跳过 |
| 2 | `zzz99-edge610-mwan3` | 改探测点；建 `wwan` 成员 + `failover` 策略并改 IPv4 规则。已有 `mwan3.wwan` 就不动 |
| 3 | `zzz99-edge610-network` | 写 `/etc/config/network`（`lan1..lan5` 桥接 + `lan6` 作 WAN）。已有 `network.lan` 就保持原样 |
| 4 | `zzz99-edge610-network-modem` | 建 `network.wwan`（qmi / cmnet / ipv4v6 / metric 100）并加入防火墙 wan zone |
| 5 | `zzz99-edge610-password` | root 密码**为空**时预置 `edge610pass`；已有密码绝不覆盖 |

装好的系统里这些脚本已经消失（自删），要看行为就用 `logread -e edge610` 和 `uci show`。

## 升级

镜像本体**没有验证过** `sysupgrade -n`：eMMC 的布局（p1 boot / p2 rootfs）与 OpenWrt x86 组合镜像一致，但分区 UUID 和 `grub.cfg` 是安装器改写的，`/boot` 默认也不挂载（`/etc/config/fstab` 里 `enabled '0'`）。按现状走重装路径：

1. 备份配置：`sysupgrade -b /tmp/cfg.tar.gz`（实测约 29 MB），再用 `scp` 或串口取出；只想要接口/拨号配置就 `tar -czf /tmp/net.tar.gz /etc/config`。
2. 新镜像刷 U 盘 → 从 U 盘启动。
3. `edge610-install --yes`。**它会整盘克隆 U 盘上的系统，eMMC 现有的 `/etc/config` 会被 U 盘那份覆盖**——这就是第 1 步必须备份的原因。
4. 断电、拔 U 盘、上电，把备份放回去（`tar -xzf /tmp/cfg.tar.gz -C /`），再 `reboot`。

如果将来要支持原地 `sysupgrade`，需要先验证它写内核/`grub.cfg` 的路径与新布局兼容，并把 `/boot` 的挂载打开。

## 串口控制台

这台机器**没有视频输出**，串口是唯一的本地入口（BIOS/POST 输出也走它）。背板小铁片后面是 Micro-USB，板载 CP210x：

| 项 | 值 |
| --- | --- |
| 参数 | `115200 8N1`，无流控 |
| 设备名 | Windows `COMx`（Silicon Labs CP210x） |
| 独占 | 一个程序占用即锁死——开桥之前先关掉 MobaXterm/PuTTY 的串口会话 |
| 远程使用 | `powershell -ExecutionPolicy Bypass -File scripts/serial-bridge.ps1`，默认监听 `:7001`（可 `$env:EDGE610_COM="COM5"` 指定口），本机可再用 raw TCP 连 `127.0.0.1:7001` 围观 |
| 跨网段 | 桥是裸 TCP；对面有 HTTP 代理时用 `CONNECT host:7001` 也能打通（本项目远程调试就是这么做的） |

```powershell
# 一次性放行端口（管理员）
netsh advfirewall firewall add rule name="edge610-serial" dir=in action=allow protocol=TCP localport=7001
```

跨网段的话，仓库里带一个客户端，省得记 CONNECT 细节：

```sh
python scripts/serial-console.py --host 10.1.2.222 --port 7001 --proxy 127.0.0.1:7897 \
    --command "uptime" --command "mwan3 status"
```

它给每条命令补 `echo __RC__$?` 并检查退出码（卡在 grub 或半行输入不会被当成成功）；`--raw` 只看串口流。

串口里看到 `root@OpenWrt:~#` 即为可用 shell；`Enter` 无反应时先发一次换行或 `Ctrl-C`（可能在 grub 菜单/长输出里）。

## 开机验收

串口执行（只读检查，也可以直接跑镜像自带的 `verify-device`）：

```sh
verify-device               # 模块 / 脚本 / 页面的自检，逐项 [ OK ]
ip link                     # 应出现 lan1..lan6（+ lo 与若干 ethX）
logread -e edge610          # 看门狗清除、conduit、端口 up 日志
df -h /                     # 安装器装的系统装完即 ~14.2G；dd 路径靠首启扩容
sensors                     # 应看到 Core 0/Core 1 温度（kmod-hwmon-coretemp）
/etc/openclash/core/clash_meta -v   # 必须回显 Mihomo Meta ... linux amd64（amd64-v1）
```

LTE 与多 WAN：

```sh
ip -br addr show wwan0      # 应有运营商地址 + IPv6
mwan3 status                # wwan online；failover 策略里应看到 wwan (100%)
ping -c 3 223.5.5.5         # 走默认路由（有线在就优先有线）
ping6 -c 2 2400:3200::1     # IPv6 不归 mwan3 管，走 netifd 默认路由
```

- 空闲运行 ≥10 分钟不重启 → 看门狗关闭生效。
- 网线接 **LAN1**，浏览器打开 `http://192.168.1.1` → LuCI（`root` / 首启密码 `edge610pass`）。
- 服务 → OpenHsalc：载入订阅配置，启动代理。
- 状态 → Modem：SIM 应显示「就绪」，首屏有信号与实时速率；`sim` 为空或红色文字说明卡没读到。

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
| 日志 `P2SB BAR unavailable` | 该机 BIOS 隐藏了 P2SB（`8086:19dd` 不在 `lspci` 里），模块从 `/proc/iomem` 的 `INTC3000:00` 反推 BAR（通常 `0xfd000000`）。注意该窗口有时在根层、有时套在根级 `Reserved` 下（`grep -n INTC3000 /proc/iomem` 看缩进），模块已改为递归扫描；仍失败时手动指定：`modprobe ... p2sb_bar_addr=0xfd000000`（详见 `docs/bringup-log.md`） |
| 4~5 分钟自动重启 | 看门狗未关：`logread -e edge610` 应无 `iSMT SMBus adapter not found`。手动确认：`modprobe i2c-ismt; grep . /sys/bus/i2c/devices/*/name`，然后 `i2cset -y <bus> 0x22 0 0 b` |
| Mihomo 报 `Illegal instruction` | 核被替换成了 v2/v3（AVX）。只可用 `linux-amd64-v1`，重新放回 `/etc/openclash/core/clash_meta` |
| 没有 WAN / 想换 WAN 口 | 默认 `lan6` 是 WAN（DHCP 客户端），`br-lan` 含 `lan1..lan5` + 两个 SFP（`eth3`/`eth2`）。换口：LuCI「网络→接口」把 `wan` 的设备改成 `lanN` / `eth2` / `eth3`（`logread -e edge610` 里的 `conduit:` 是交换 uplink，**不要**配地址） |
| 从 U 盘启动却进了 eMMC 系统 | 镜像的分区 UUID 固定，同一个镜像刷到 eMMC 和 U 盘后两块盘 `PARTUUID` 相同，内核会挂到先枚举到的 eMMC。用 `scripts/usb-prep.sh /dev/sdX` 重新生成 U 盘 p2 的 UUID 并同步改其 `grub.cfg`（详见 `docs/bringup-log.md`），或在 GRUB 里改成 `root=/dev/sdb2` |
| 装到 eMMC 后停在裸 `grub>` 提示符 | `core.img` 是按"boot 文件系统在 **gpt1**"编的。手工分区把 FAT 放到 gpt2（例如在 34..511 先建一个 BIOS boot 分区）就会这样，菜单和 `grub.cfg` 都不加载。用 `edge610-install` 写表（FAT 固定在 512 = p1），或在 `grub>` 里 `configfile (hd0,gptN)/boot/grub/grub.cfg` 手工引导后改表 |
| `wwan0` 有地址却 `ping: Network unreachable` | mwan3 在跑但 `/etc/config/mwan3` 里没有 `wwan`：它把流量标记进空策略。补 `wwan` 接口 + 成员 + 策略（本镜像首启已做），或 `/etc/init.d/mwan3 disable && stop` 交回 netifd |
| 某条 WAN 明明通却被判 down | mwan3 探测点被墙。包默认的 `1.1.1.1` / `1.0.0.1` / `114.114.114.114` 在本地实测丢包或不回；首启脚本已改成 `9.9.9.9` / `8.8.8.8` / `223.5.5.5`，自定义时别用 ICMP 被过滤的地址 |
| `edge610-install` 报 `cannot find /dev/mmcblk0p2 after the write` | v2026.11.13 之前的安装器：克隆来的 GPT 描述的是 U 盘大小，放到更小的 eMMC 上内核直接拒绝。换新镜像，或用新镜像里的安装器覆盖 `/usr/sbin/edge610-install` |
| `+CPIN?` 回 `SIM failure` / 换卡后不识别 | SIM 检测线被 `AT!CUSTOM="SIMHOTSWAPDIS",1` 屏蔽，热插拔后模组不会自己重新初始化：点模组「设置」页的**复位模组**（约 50 秒恢复）。卡必须插**上槽**（`AT!UIMS=0`） |
| eth 口数量不止 eth0/eth1 | X553 共 4 个 MAC，枚举数量随 BIOS 变化；以日志中 `conduit:` 行与实际插线为准 |

## 修改与重建

- 改镜像内容：编辑 `package/edge610-board/` 或 workflow 中的 `.config` 种子 → commit。**CI 只在手动触发时跑**（`workflow_dispatch`）：Actions → *Build Edge 610 OpenWrt Image* → *Run workflow*；本地迭代用 `PROXY=... ./scripts/build-local.sh`（增量，改包通常 3~10 分钟）。
- `.config` 种子中的关键包在构建时会被断言（defconfig 后 grep 校验），缺失即失败，避免“构建成功但内容不对”。
- 构建末尾会校验：镜像存在且大小合理、manifest 含关键包、rootfs 内含模块与脚本、`hsalc_meta` 可执行且回显 Mihomo。

## 已知限制

| 项 | 说明 |
| --- | --- |
| mwan3 只管 IPv4 | IPv6 用 netifd 的默认路由（`wwan0` 原生 `/128`，`default_rule_v6` 已删），没有 IPv6 故障切换 |
| LTE 探测有流量 | `wwan` 每 30 s 两个 ICMP ≈ 0.6 MB/天；计量卡可把 `mwan3.wwan.interval` 调大或停用 mwan3 |
| 换卡 / 拔插要复位 | SIM 检测线被屏蔽，插入后不会自己重新初始化（见故障排查） |
| 只能用上槽 | 下槽在 Edge 610 上没接线，`AT!UIMS=2` 该固件直接 `ERROR` |
| AT 页无命令白名单 | 有 LuCI 权限即可发 `AT!RESET` / `AT!USBCOMP`，改错会丢 AT 口 |
| 同镜像两盘共存 | 安装器刻意不改 FAT 序列号（GRUB 把它编进 `core.img`），两块同镜像的盘序列号相同；`root=` 各自独立，只有 `/boot` 的内核文件可能来自另一块盘。自测时用 `scripts/usb-prep.sh` |
| OpenClash 不在本仓库 | 只预置包与内核，订阅/规则/运行状态由用户管理 |

## 版本与发布

- Tag 形如 `v2026.11.13`（发布日期），指向构成本镜像的提交；`README` 与 `docs/` 随同一提交发布。
- 每个 release 附：`edge610-YYYYMMDD-HHMM.img.gz`、同名 `.manifest`、`edge610-board` 与三个 kmod 的 `.apk`（r2，供设备上升级 / ImageBuilder）、`sha256sums`。
- 发版前的最低验证：`edge610-install --yes` 装到 eMMC → 断电拔盘 → 无人启动 → `mwan3 status` 里 `wwan online` + `failover` → IPv4/IPv6 各 ping 一次 → LuCI 模组页 200。
- 本机构建产物在 `~/work/artifacts/`（含 `repo/` 下的 .apk），镜像 sha256 由 `sha256sum` 生成后写进 release 正文与 `sha256sums`。
