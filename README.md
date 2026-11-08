# Edge 610 OpenWrt 固件自动构建

为 **VMware SD-WAN Edge 610**（Dell EMC VEP1400 同款硬件）定制的 OpenWrt 镜像，GitHub Actions 一键全源码构建。

- 目标机：Intel Atom C3338（无 AVX/AVX2）/ 4GB DDR4 / 16GB eMMC（`/dev/mmcblk0`）/ 无显示输出（Micro-USB 串口 115200 8N1）
- 交换：2× SFP（SoC 原生 X553，`ixgbe`）+ 6× RJ45（板载 Marvell 88E6190，DSA `lan1..lan6`）
- 看门狗：板载 PIC 硬件 WDT（iSMT SMBus `0x22/0x24`），开机由脚本清除，否则 4~5 分钟硬重启

> 为什么不用 ImageBuilder：官方 x86 预编译内核关闭了 `CONFIG_NET_DSA` / `MV88E6XXX`，没有 `i2c-ismt`，也无法编译本机所需的外挂内核模块。因此本仓库改为 **全源码构建** OpenWrt 25.12.6。

## 构建产物

Actions 运行成功后下载 artifact `Edge610-OpenWrt-Image`（zip 内）：

| 文件 | 说明 |
| --- | --- |
| `openwrt-x86-64-generic-ext4-combined-efi.img.gz` | **刷机用镜像**（EFI，根分区 1024MB） |
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
| OpenClash | 0.48.002（官方稳定 release tag） |
| Mihomo 内核 | v1.19.33 `linux-amd64-v1`（**无 AVX2**，预置于 `/etc/openclash/core/clash_meta`） |
| DNS | `dnsmasq-full`（替换默认 dnsmasq） |
| 交换 | `kmod-dsa` + `kmod-dsa-mv88e6xxx` + 本仓库 `edge610_dsa`（端口名 `lan1..lan6`） |
| 网卡 | `kmod-ixgbe`（**autoload 已剥离**，由 init 脚本按序加载） |
| 看门狗总线 | `kmod-i2c-ismt` + `i2c-tools` |
| 默认网络 | `br-lan` = `lan1..lan6`，静态 `192.168.1.1/24`；**无默认 WAN** |
| 预置插件 | LuCI 中文、`luci-app-ttyd`（Web 终端）、`luci-app-package-manager`、`luci-app-statistics`、`luci-app-ddns`、`luci-app-sqm`、`luci-proto-wireguard` |
| 诊断工具 | `ethtool` `tcpdump` `htop` `mtr` `iperf3` `iftop` `bind-host`(dig) `nano` `pciutils`(lspci) `usbutils`(lsusb) `lm-sensors` `block-mount` |
| USB 扩展 | `kmod-usb-net-rtl8152` / `asix-ax88179` / `cdc-ether`（USB 网卡或手机共享作 WAN）、`kmod-usb-storage`、`kmod-fs-ext4` |

## 仓库结构

```
.github/workflows/build.yml       全源码构建流水线（14 步，含断言与镜像校验）
package/edge610-board/
├── Makefile                      三个内核包 + 板级包定义
├── src/
│   ├── edge610_switch_standalone.c   ixgbe 加载前初始化 X553/交换芯片
│   ├── edge610_dsa.c                 注册 88E6190 DSA（端口 lan1..lan6）
│   └── Makefile
└── files/
    ├── etc/init.d/edge610           看门狗关闭 + 有序探测（standalone → ixgbe → DSA）
    ├── etc/modprobe.d/edge610.conf  板级模块参数
    ├── etc/uci-defaults/zzz99-edge610-network  首启网络配置
    └── etc/openclash/core/          clash_meta 由 CI 下载（已 gitignore）
```

### 关键设计

- **加载顺序**：`ixgbe` 的 autoload 在构建时被删除，`/etc/init.d/edge610`（START=19，早于 network）依次执行：
  `modprobe edge610_switch_standalone cpu_port=10 x553_sgmii=1 cpu_mac_ctl=0x203e serdes_autoneg=1` → `modprobe ixgbe` → `modprobe mv88e6xxx` → `modprobe edge610_dsa conduit_name=<ethX>`。
- **conduit 检测**：优先 PCI `0000:03:00.0` 的 netdev；回退取 ixgbe 中 MAC 最小的网口（conduit 是四个连续 X553 MAC 的第一个）。conduit 口只置 up，不配地址。
- **看门狗**：扫描 `/sys/bus/i2c/devices/*/name` 中的 `iSMT` 适配器，向 `0x22`/`0x24` 写 `0x00`；失败仅记录日志，不阻塞启动。
- **端口改名**：`edge610_dsa` 中端口名由上游 `ge1..ge6` 改为 `lan1..lan6`，与 OpenWrt DSA 惯例及网络默认配置一致。
- **根分区**：`CONFIG_TARGET_ROOTFS_PARTSIZE=1024`（默认 104MB 装不下 mihomo + ruby 等）。

## 刷机

1. 解压 artifact 得到 `openwrt-x86-64-generic-ext4-combined-efi.img`，用 Rufus / BalenaEtcher 以 DD 模式写入 U 盘。
2. 拆背板小铁片露出 Micro-USB 串口（CP210x），PuTTY：`115200 8N1`、无流控。
3. 插 U 盘开机，F12 选 USB 启动，进入 OpenWrt 后：
   ```sh
   lsblk                                   # 确认 /dev/mmcblk0 为内置 eMMC，/dev/sda 为 U 盘
   dd if=/dev/sda of=/dev/mmcblk0 bs=4M status=progress conv=fsync
   reboot                                  # 拔 U 盘，从 eMMC 启动
   ```

## 开机验收

串口执行：

```sh
ip link                     # 应出现 lan1..lan6（+ lo 与若干 ethX）
logread -e edge610          # 看门狗清除、conduit、端口 up 日志
/etc/openclash/core/clash_meta -v   # 必须回显 Mihomo Meta ... linux amd64（amd64-v1）
```

- 空闲运行 ≥10 分钟不重启 → 看门狗关闭生效。
- 网线接 **LAN1**，浏览器打开 `http://192.168.1.1` → LuCI。
- 服务 → OpenClash：载入订阅配置，启动代理。

## 故障排查

| 现象 | 处理 |
| --- | --- |
| `ip link` 无 `lan1..lan6` | `logread -e edge610` 看 `edge610_switch_standalone` / `edge610_dsa` 报错；`dmesg \| grep -i -E 'dsa\|mv88e'`；`lsmod \| grep -E 'edge610\|mv88e\|dsa'` |
| 日志 `P2SB BAR unavailable` | 该机 BIOS 隐藏了 P2SB（`8086:19dd` 不在 `lspci` 里）。模块会从 `/proc/iomem` 的 `INTC3000:00` 反推 BAR（通常 `0xfd000000`）；仍失败时手动指定：`modprobe edge610_switch_standalone p2sb_bar_addr=0xfd000000 ...` 和 `modprobe edge610_dsa conduit_name=ethX p2sb_bar_addr=0xfd000000` |
| 4~5 分钟自动重启 | 看门狗未关：`logread -e edge610` 应无 `iSMT SMBus adapter not found`。手动确认：`modprobe i2c-ismt; grep . /sys/bus/i2c/devices/*/name`，然后 `i2cset -y <bus> 0x22 0 0 b` |
| Mihomo 报 `Illegal instruction` | 核被替换成了 v2/v3（AVX）。只可用 `linux-amd64-v1`，重新放回 `/etc/openclash/core/clash_meta` |
| 没有 WAN | 默认只配 LAN。LuCI → 网络 → 接口 → 添加，设备选 SFP 对应的 `ethX`（`logread -e edge610` 里的 `conduit:` 是交换 uplink，**不要**配地址） |
| eth 口数量不止 eth0/eth1 | X553 共 4 个 MAC，枚举数量随 BIOS 变化；以日志中 `conduit:` 行与实际插线为准 |

## 修改与重建

- 改镜像内容：编辑 `package/edge610-board/` 或 workflow 中的 `.config` 种子 → commit 推送 → Actions 重跑。
- `.config` 种子中的关键包在构建时会被断言（defconfig 后 grep 校验），缺失即失败，避免“构建成功但内容不对”。
- 构建末尾会校验：镜像存在且大小合理、manifest 含关键包、rootfs 内含模块与脚本、`clash_meta` 可执行且回显 Mihomo。
