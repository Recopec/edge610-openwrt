# Edge 610 OpenWrt Firmware Build

[简体中文](README.md) | **English**

A full-source OpenWrt image for the **VMware SD-WAN Edge 610** (same hardware as the Dell EMC VEP1400), built by GitHub Actions.

- Target: Intel Atom **C3308** (2C/2T 1.6 GHz, no AVX/AVX2) / 4 GB DDR4 / 16 GB eMMC (`/dev/mmcblk0`, 14.6 GiB usable) / no video output (Micro-USB serial console, 115200 8N1)
- Network: 2× **1G SFP** (native X553, `ixgbe`) + 6× **1G RJ45** (on-board Marvell 88E6190, DSA `lan1..lan6`) — every port is capped at 1G, see [Port speed limits](#port-speed-limits)
- Watchdog: on-board PIC hardware WDT (iSMT SMBus `0x22/0x24`); the boot script clears it, otherwise the box reboots after 4–5 minutes

## Screenshots

| Status overview |
| --- |
| ![Status overview](docs/screenshots/01-overview.png) |

| Network interfaces | Realtime traffic (gigabit saturated) |
| --- | --- |
| ![Network interfaces](docs/screenshots/02-network.png) | ![Realtime traffic](docs/screenshots/04-realtime.png) |

| Mount points (rootfs already grown) | Docker |
| --- | --- |
| ![Mount points](docs/screenshots/05-mounts.png) | ![Docker](docs/screenshots/06-docker.png) |

> Captured on real hardware: Argon v3 theme, Chinese UI. The box in the screenshots uses `10.1.2.3/24`; the image defaults to `192.168.1.1/24`.

### 4G/LTE modem (EM7565)

Status → **Modem** has five tabs, all supplied by this repo's `edge610-board` package — no extra plugin:

| Tab | Contents |
| --- | --- |
| Status | The answer first: link (carrier / RAT / band / attach), signal (RSRP as the headline plus SINR/RSRQ and a 60-sample sparkline), live down/up rates and session totals; below that serving cell, connection & registration, signal bars, data connection, hardware, neighbours (intra / inter frequency), modem state |
| Settings | SIM slot (`AT!UIMS`), RAT (`AT!SELRAT`), network scan / auto select, APN and auth, band lock (`AT!BAND`, changing it redials); **Reset modem** in the header (`AT+CFUN=1,1`) |
| GPS | Start/stop, latitude/longitude and time-to-first-fix, satellites in view (elevation / azimuth / SNR), raw `AT!GPSSTATUS?;!GPSLOC?;!GPSSATINFO?` |
| SMS | Send, inbox (delete per message), sent items (delete / clear) |
| AT | Raw AT console: quick commands, timeout, `;` chaining, copy output |

| Status (the answer on top) |
| --- |
| ![Modem status](docs/screenshots/07-modem-status.jpg) |

| Settings | GPS |
| --- | --- |
| ![Modem settings](docs/screenshots/08-modem-settings.jpg) | ![GPS](docs/screenshots/09-modem-gps.jpg) |

| SMS | AT |
| --- | --- |
| ![SMS](docs/screenshots/10-modem-sms.jpg) | ![AT console](docs/screenshots/11-modem-at.jpg) |

Beyond the pages, the image also ships:

- **Interface on first boot**: `zzz99-edge610-network-modem` creates `network.wwan` (qmi / `/dev/cdc-wdm0` / `apn cmnet` / `pdptype ipv4v6` / `metric 100`) and adds it to the firewall `wan` zone; `/etc/config/network` is left alone when a `lan` interface already exists.
- **Egress order**: the wired `lan6` (WAN, DHCP, metric 0) wins and LTE is the metric 100 fallback — netifd only falls back when the wired default route disappears. There are no health checks; enable mwan3 (off by default) if you want active failover.
- **`modem-at`**: probes for the AT port (the option driver's index follows the USB composition — `ttyUSB1` or `ttyUSB2`) and takes a `flock` so it never races the page.
- **`modem-wan-watch`**: 30 s loop. Every 60 s it reads slot 1 over QMI; two consecutive non-`present` readings → `ifdown wwan` + `AT+CFUN=1,1` (throttled to 10 min), and `ifup` once the card is readable and `auto=1`. It also compares `AT+CGPADDR` with the `wwan0` address and redials when the PDP address drifts (backoff 120→900 s).
- **What "rate" means**: QMI WDS only reports session parameters (IP / gateway / DNS / MTU) — there is no negotiated-rate field. Radio capability comes from `AT!GSTATUS?` (band / bandwidth / CA), throughput from `wwan0` counters — the headline down/up rate is the average between two polls, so a longer refresh interval is smoother.

Known limits:

- **A new SIM needs a reset**: the card-detect line is masked with `AT!CUSTOM="SIMHOTSWAPDIS",1`, so the modem does not re-initialise after a hot swap. Hit **Reset modem** once; measured recovery to registration and dial-up is about 50 s.
- **Slot 1 only**: `AT!UIMS=0` selects the wired slot 1, `AT!UIMS=1` is unwired slot 2, and `AT!UIMS=2` answers `ERROR` on this firmware.
- **The AT page has no command whitelist**: anyone with LuCI rights can send `AT!RESET` or `AT!USBCOMP` and lose the AT port. A few queries (e.g. `AT!SELRAT?`) return `Unknown RAT mode` when chained, so send them alone.

> IMEI / IMSI / ICCID / MSISDN / SMS verification code / coordinates are redacted in these screenshots.

## Hardware photos

| Front | Rear |
| --- | --- |
| ![Front](docs/hardware/front.jpg) | ![Rear](docs/hardware/back.jpg) |

> Rear panel, left to right: MAIN/GPS antenna connectors, 2× SFP (labelled 1/2), GE1/GE2, GE3/GE4, AUX; the Micro-USB console sits behind the small metal cover.

## Hardware (measured)

| Item | Value |
| --- | --- |
| CPU | `Intel(R) Atom(TM) CPU C3308 @ 1.60GHz` (2C/2T, no AVX/AVX2) |
| RAM | 4,003,672 kB ≈ 3.8 GiB |
| eMMC | `mmc0:0001 AJTD4R` 14.6 GiB (`/dev/mmcblk0`; HS400, ~293 MB/s sequential read). Image layout: p1 **128M** vfat `/boot`, p2 rootfs, p128 239K BIOS boot. p1 holds the keep-config upgrade backup; 16M cannot take a backup that includes openclash |
| NIC | 4× `8086:15c3` X553 Backplane (BIOS reports chip type **X550**) |
| Port mapping | `eth0` = `03:00.0` = switch CPU link (**CPU port 10**, conduit); `eth1` = `03:00.1` unused; `eth2` = `05:00.0`, `eth3` = `05:00.1` = the two SFP ports |
| SFP speed | **1G only** (no 2.5G, no 10G). Dell spec: Edge 610 = `2×1G SFP`, only 620/640/680 get `2×10G SFP+`. All four X553 functions are `8086:15c3` = `X550EM_A_KR_L` (1G backplane variant) and the driver returns 1G for that device ID. Forcing 2.5GBASE-X (`x553_speed=2500` + switch `MAC_CTL=0x303f`) still links at 1G |
| WiFi | `168c:003c` QCA986x/988x (ath10k + `ath10k-firmware-qca988x`) |

> Why not ImageBuilder: the official x86 prebuilt kernel has `CONFIG_NET_DSA` / `MV88E6XXX` disabled, ships no `i2c-ismt`, and cannot compile the out-of-tree modules this board needs. This repo therefore builds OpenWrt 25.12.6 from source.

## CPU benchmark

The C3308 has no PassMark entry (too obscure), so it was measured with **CoreMark 1.0** (this device, OpenWrt 25.12.6, idle):

| Item | Measured |
| --- | --- |
| CoreMark 1.0 (single) | **7,786.51** iterations/sec (110,000 iterations, 14.13 s, CRC validated) |
| CoreMark 1.0 (2 threads) | **14,582.09** (`-DMULTITHREAD=2 -DUSE_FORK=1`, scaling 1.87×) |
| Per MHz | 7,786 / 1600 ≈ **4.87 CoreMark/MHz** (Goldmont out-of-order core) |
| Compiler | GCC 14.3.0 (OpenWrt toolchain), `-O2 -DPERFORMANCE_RUN=1 -lrt` |
| Reference (single) | Raspberry Pi 4 @1.5 GHz: 8,257; RPi 3: 3,800; i5-3320M: 21,245; i3-10100: 30,532 |
| Reference (PassMark) | Sibling C3338: single 1,028 / multi 1,834 (C3308 clocks lower, same class) |

OpenSSL crypto (`openssl speed`, AES-NI active):

| Algorithm | 1 KB | 16 KB |
| --- | --- | --- |
| AES-128-CBC | 411 MB/s | 418 MB/s |
| AES-256-GCM | 403 MB/s | 547 MB/s |
| SHA-256 | 300 MB/s | 381 MB/s |
| ChaCha20-Poly1305 | 261 MB/s | 271 MB/s |

Reproduce:

```bash
git clone --depth 1 https://github.com/eembc/coremark.git && cd coremark
make PORTABLE=1 PORT_DIR=linux \
  CC=<staging_dir>/toolchain-x86_64_gcc-14.3.0_musl/bin/x86_64-openwrt-linux-musl-gcc \
  ITERATIONS=100000
# copy coremark.exe to the device and run ./coremark
```

## Other onboard hardware (measured)

| Hardware | State |
| --- | --- |
| **Sierra Wireless EM7565** LTE-A Cat-12 module (USB `1199:9091`, SN `UF04360020011048`) | Built into the image since `ec39bbf`: the option driver provides the AT ports, `qmi_wwan` provides `wwan0` + `cdc-wdm0`. Back panel MAIN/AUX = LTE main/aux antennas, **GPS = GNSS antenna**. Test notes: [docs/lte.en.md](docs/lte.en.md) |
| **GPS/GNSS** | The EM7565's positioning (GPS/GLONASS/BeiDou/Galileo/QZSS), used by SD-WAN for device location; readable via QMI LOC or `AT!GPS`, needs the GPS antenna |
| **Cell parameters** | PCI/ECGI/TAC/neighbours/signal/APN command reference: [docs/lte-cell-info.en.md](docs/lte-cell-info.en.md) · [full AT command list](docs/lte-at-commands.en.md) |
| **Intel QuickAssist (QAT)** `8086:19e2` | Crypto/compression co-processor; no driver in OpenWrt (needs out-of-tree Intel qat17), disabled |
| **QCA988x WiFi 5** `168c:003c` | ath10k works; shipped config has `disabled '1'`, after `wifi reload` `phy0-ap0` (5 GHz/80 MHz/23 dBm) comes up |
| **SD Host controller** `8086:19db` | Drives the onboard eMMC (HS400); no second mmc device |
| **SMBus devices** | `0x22`/`0x24` = PIC (watchdog control, written 0 at boot); `0x40` = PSU/telemetry; `0x50–0x57` = EEPROM/FRU; `0x20/0x21` etc. are write-only |
| **Temperatures** | coretemp 50–56 °C; 8 switch port sensors 55–57 °C |
| **ME (HECI)** `8086:19d3` | Present, unused |

## Port speed limits

| Interface | Limit | Basis |
| --- | --- | --- |
| 6× RJ45 `lan1..lan6` | **1G per port** | Marvell 88E6190 is a gigabit switch |
| 2× SFP | **1G** | Dell spec: Edge 610 = `2×1G SFP`; X553 is `8086:15c3` (KR_L, 1G backplane) |
| Internal CPU link (switch ↔ X553) | **1G** | Hardware can be set to 2.5GBASE-X, but forcing it still links at 1G |

- **No 2.5G**: the SFP driver capability table only has 1G/10G; the CPU link does not come up at 2.5G in practice (`x553_speed=2500` + `MAC_CTL=0x303f` still 1G).
- **No 10G**: 10G SFP+ exists only on Edge 620/640/680 (4/8/16 cores); the 610's X553 is strapped as KR_L (1G).
- Want 2.5G/10G? Use a 620 or above, or add a USB 2.5G NIC (the image already ships `kmod-usb-net-rtl8152`).

### SFP ports, as measured

| Item | Result |
| --- | --- |
| Port mapping | Only the matching netdev returns the module EEPROM, so **SFP1 = `eth3` (`05:00.1`)** and SFP2 = `eth2` (`05:00.0`) |
| Default config | Both cages are `br-lan` members (`lan1..lan5` + `eth3` + `eth2`), usable as soon as a cable is plugged in; `lan6` is the WAN |
| Modules | Copper SFP `OYJ-SFP-T` (OEM, 1.25G, serials `82608030053` / `82608150004`, dated 2026-11-04) |
| Link | SFP1 against a 1G peer: `NIC Link is Up 1 Gbps, Flow Control: RX/TX`, full duplex, `rx_errors`/`rx_crc_errors` = 0 |
| Bring-up timing | After `ip link set up` the module PHY needs ~2 s, so the first events are an `Up -> Down` pair; an empty cage stays `NO-CARRIER` |
| Speed negotiation | The host side is fixed 1G SGMII/backplane (`Supported link modes: 1000baseKX`); 10/100M is negotiated by the module's own PHY |
| DDM | Copper parts return placeholder A2 pages (two different serials are byte-identical and report Rx power without optics); A2 `0x0180` onwards is all zeroes, so it is useless for monitoring |
| Hot-plug | A module is detected as soon as it is inserted (EEPROM readable), no extra driver needed; the port is a permanent bridge member |

**Why there is no 2.5G/10G on the 610**:

- All four ports are `8086:15c3` = `X550EM_A_KR_L`; `ixgbe_get_link_capabilities_X550em()` returns 1G unconditionally for `phy.type == x550em_kr` + `device_id == KR_L`.
- 2.5G is only reported when the port's NVM strap `IXGBE_NW_MNG_IF_SEL` (CSR `0x11178`) has `PHY_SPEED_2_5G` (bit 20) set - it is not set here, and no module can change that.
- 10G needs an `X550EM_A_SFP` (`15ce`) / `SFP_N` (`15c4`) / `KR` (`15c2`) SKU; `allow_unsupported_sfp=1` does not help either, because KR_L takes the `x550em_kr` path and never calls the SFP whitelist.

| Model | SFP ports | X553 configuration |
| --- | --- | --- |
| Edge 610 | 2x **1G SFP** | KR_L (`15c3`) |
| Edge 620 / 640 / 680 | 2x **1G/10G SFP+** | SFP / SFP_N (`15ce` / `15c4`) |

> The Edge 600 series is 610/620/640/680 (plus 610C/610N/620C/620N/640N variants); **there is no 630**.


## Build artifacts

After a successful Actions run, download the `Edge610-OpenWrt-Image` artifact (zip):

| File | Description |
| --- | --- |
| `openwrt-x86-64-generic-ext4-combined-efi.img.gz` | **Flashable image** (EFI, 1024 MB rootfs, build-system default name) |
| `edge610-YYYYMMDD-HHMM.img.gz` | Same image with a **timestamped name** (GMT+8; produced by CI and local builds) |
| `openwrt-x86-64.manifest` | Installed package list |
| `sha256sums` | Checksums |

## Building

1. Actions → **Build Edge 610 OpenWrt Image** → *Run workflow* (main branch).
2. About 3.5–4 hours on a 4-core runner (full source build + toolchain). On failure a `build-log` artifact (`build.log` / `dl.log`) is uploaded automatically.

### Local build (recommended for iteration)

CI uses a fresh runner every time and must rebuild rustc + the toolchain (~70% of the time). A local VM keeps the cache: **~75 minutes for the first run, typically 3–10 minutes for later package changes**.

```bash
# Requirements: Ubuntu 24.04 x86_64, >=8 cores, >=16 GB RAM, >=60 GB free disk (ext4)
PROXY=http://192.168.68.1:7897 ./scripts/build-local.sh
```

- `PROXY` is optional: set it when GitHub / OpenWrt mirrors are flaky on your network.
- The script mirrors CI exactly (same feeds pin, same `.config` seed, same ixgbe autoload strip, same final checks) and is idempotent.
- Output: `~/work/openwrt/bin/targets/x86/64/openwrt-x86-64-generic-ext4-combined-efi.img.gz`
- Download resilience is built in: `CURL_OPTIONS` with a 600 s per-file cap and a 60 s low-speed abort, retried 3 times.

## Image contents

| Component | Version / notes |
| --- | --- |
| OpenWrt | 25.12.6 (x86_64, kernel 6.12.112) |
| LuCI | official feed |
| OpenHsalc | 0.48.002 (official stable release tag) |
| Mihomo core | v1.19.33 `linux-amd64-v1` (**no AVX2**, preinstalled at `/etc/openhsalc/core/hsalc_meta`) |
| DNS | `dnsmasq-full` (replaces the default dnsmasq) |
| Switching | `kmod-dsa` + `kmod-dsa-mv88e6xxx` + this repo's `edge610_dsa` (ports named `lan1..lan6`) |
| NIC driver | `kmod-ixgbe` (**autoload stripped**, loaded in order by the init script) |
| Watchdog bus | `kmod-i2c-ismt` + `i2c-tools` |
| Temperature | `kmod-hwmon-coretemp` + `lm-sensors` (Denverton via MSR; `/sys/class/thermal` has zones) |
| CPU microcode | `intel-microcode` (20251111; kernel `CONFIG_MICROCODE_LATE_LOADING`, preinit writes `/sys/devices/system/cpu/microcode/reload`. Without it the boot log shows `sh: write error: Invalid argument` and the CPU stays at its factory revision, leaving RFDS and friends unmitigated) |
| WiFi | `kmod-ath10k` + `ath10k-firmware-qca988x` (QCA986x/988x on board, no interface configured by default) |
| Default network | `br-lan` = `lan1..lan5` + `eth3`/`eth2` (both SFP cages), static `192.168.1.1/24`; **`lan6` is the WAN** (DHCP client, metric 0) |
| Rootfs | 1 GiB in the image; **grows to the whole eMMC on first boot** (`sfdisk` + `partx` + `resize2fs`) |
| Default password | A fresh install presets root's password to `edge610pass` (`zzz99-edge610-password` only writes when root's hash in `/etc/shadow` is empty; keep-config upgrades never touch a password the user changed). **Change it after the first login** |
| Theme | **Argon v3** (`jerrykuku/luci-theme-argon`, master; config page is part of the theme since v3) |
| Base apps | Chinese LuCI, `ttyd` (web terminal), `package-manager`, `statistics`, `ddns`, `sqm`, `wireguard`, `firewall` |
| Security / certs | `acme` + `uhttpd` (Let's Encrypt HTTPS), `banip` (brute-force bans), `acl` (multi-user permissions) |
| Virtualization | `lxc` |
| Acceleration / mesh | `kmod-tcp-bbr` (BBR congestion control), `zerotier` (via iStore GUI), `luci-app-wifischedule` |
| Time / speed / traffic | `chrony` (precise time), `librespeed` (LAN speed test, verifies gigabit line rate), `vnstat2` (traffic history) |
| Networking | `mwan3` (multi-WAN, pairs with the two SFP ports), `pbr` (policy routing), `upnp`, `nlbwmon`, `wol`, `udpxy` (IPTV multicast-to-unicast), `omcproxy`, `lldpd` |
| DNS / ad blocking | **not preset** (`apk add luci-app-adguardhome` / `luci-app-smartdns` / `luci-app-adblock-fast` as needed) |
| Storage / sharing | `ksmbd` (SMB), `hd-idle`, `filebrowser` (aria2/transmission via `apk add`) |
| Disks / filesystems | `kmod-fs-exfat` / `vfat` / `ntfs3`, `kmod-usb-printer`, `e2fsprogs`, `smartmontools`, `hdparm` |
| Operations | `commands`, `irqbalance`, `p910nd` (USB printing), `ser2net`, `filemanager` |
| VPN / tunneling | kernel + protocol only (`kmod-wireguard`, `wireguard-tools`, `luci-proto-wireguard`); openvpn/tailscale/frpc via `apk add` |
| Containers | **Docker built in**: `dockerd`/`containerd`/`runc`/`tini`/`docker` CLI/`docker-compose` + `luci-app-dockerman` (kernel deps veth/ipt-nat/ipt-physdev/nf-ipvs included) |
| Diagnostics | `ethtool` (full variant, `-m` decodes SFP EEPROM) `tcpdump` `htop` `mtr` `iperf3` `iftop` `bind-host`(dig) `nano` `pciutils`(lspci) `usbutils`(lsusb) `lm-sensors` `block-mount` |
| USB expansion | `kmod-usb-net-rtl8152` / `asix-ax88179` / `cdc-ether` (USB NIC or phone tethering as WAN), `kmod-usb-storage`, `kmod-fs-ext4` |

## Repository layout

```
.github/workflows/build.yml       full-source build pipeline (14 steps, assertions + image checks)
patches/openwrt/0001-image-mkfs-ext4-use-mke2fs.patch  build the rootfs with mke2fs (online resize)
package/edge610-board/
├── Makefile                      three kernel packages + board package
├── src/
│   ├── edge610_switch_standalone.c  initialise X553/switch before ixgbe probes
│   ├── edge610_dsa.c                register the 88E6190 DSA (ports lan1..lan6)
│   └── Makefile
└── files/
    ├── etc/init.d/edge610           watchdog off + ordered bring-up (standalone -> ixgbe -> DSA)
    ├── etc/modprobe.d/edge610.conf  board module parameters
    ├── etc/uci-defaults/zzz99-edge610-network  first-boot network (lan1..lan5 LAN, lan6 WAN)
    ├── etc/uci-defaults/zzz99-edge610-network-modem  first-boot network.wwan (LTE)
    ├── usr/bin/modem-at            AT port probe + flock
    ├── usr/bin/modem-wan-watch     SIM / PDP address watchdog
    ├── usr/lib/lua/luci/controller/modem.lua         modem page backend (AT/QMI)
    ├── usr/lib/lua/luci/view/modem/                  Status / Settings / GPS / SMS / AT
    └── etc/openhsalc/core/          hsalc_meta downloaded by CI (gitignored)
```

### Key design notes

- **Load order**: `ixgbe` autoload is removed at build time; `/etc/init.d/edge610` (START=19, before network) runs:
  `insmod edge610_switch_standalone cpu_port=0 x553_sgmii=1 cpu_mac_ctl=0x203e serdes_autoneg=1` → `modprobe ixgbe` → `modprobe mv88e6xxx` → `insmod edge610_dsa conduit_name=<ethX> force_cpu_phyctl=0x203e`.
  (busybox `modprobe` silently drops `name=value` arguments, so the board modules are loaded with `insmod`.)
- **Conduit detection**: prefer the netdev of PCI `0000:03:00.0`; fall back to the ixgbe port with the lowest MAC (the conduit is the first of four consecutive X553 MACs). The conduit is only brought up, never assigned an address.
- **Watchdog**: scan `/sys/bus/i2c/devices/*/name` for the `iSMT` adapter and write `0x00` to `0x22`/`0x24`; failures are logged but never block boot.
- **Port renaming**: `edge610_dsa` renames the upstream `ge1..ge6` ports to `lan1..lan6`, matching OpenWrt DSA conventions and the default network config.
- **Rootfs**: `CONFIG_TARGET_ROOTFS_PARTSIZE=1024` (the 104 MB default cannot hold mihomo + ruby); `zzz98-edge610-resize` grows it to the whole disk on first boot.
  This requires the image to be built with `mkfs.ext4` instead of OpenWrt's default `make_ext4fs`: the latter's resize inode layout makes the kernel reject online growth with
  `reserve_backup_gdb: reserved block 64 not at offset 63` ([openwrt#7729](https://github.com/openwrt/openwrt/issues/7729)).
  This repo replaces `Image/mkfs/ext4` via `patches/openwrt/0001-image-mkfs-ext4-use-mke2fs.patch` (running under fakeroot with `chown -R 0:0` so files stay root-owned).

## Board packages only (no reflash)

If the box already runs **OpenWrt 25.12.6 / kernel 6.12.112**, you can install just the board packages instead of flashing the full image.

Build (inside the OpenWrt source tree, with this repo's `package/edge610-board`):

```sh
make package/edge610-board/compile V=s
```

Outputs:

| File | Description |
| --- | --- |
| `bin/packages/x86_64/base/edge610-board-*.apk` | board package: init script + modprobe parameters + first-boot network + mihomo core (~25 MB) |
| `bin/targets/x86/64/packages/kmod-edge610-switch-*.apk` | switch initialisation module |
| `bin/targets/x86/64/packages/kmod-edge610-dsa-*.apk` | DSA registration module |
| `bin/targets/x86/64/packages/kmod-i2c-ismt-*.apk` | watchdog bus driver |

Install:

```sh
apk add --allow-untrusted ./kmod-i2c-ismt-*.apk ./kmod-edge610-switch-*.apk \
    ./kmod-edge610-dsa-*.apk ./edge610-board-*.apk
/etc/init.d/edge610 enable
reboot
```

Notes:

- **kmod packages are locked to the kernel version** (`6.12.112`); a different kernel will refuse to load them.
- On a stock image `ixgbe` autoloads at boot and probes *before* `/etc/init.d/edge610`, so the X553 SGMII mode is never applied.
  With packages only, first remove the ixgbe autoload entry (`/etc/modules.d/`, ixgbe-related file) and let the init script load it in order; otherwise use the full image.

## Flashing

> Use an image built from this repo (mke2fs patch applied). Images built with OpenWrt's default `make_ext4fs` fail the first-boot online resize (openwrt/openwrt#7729).

1. Prepare a USB stick: one OpenWrt boot disk plus an exfat data partition, and put `edge610-*.img.gz` on the data partition.
2. Remove the small rear cover to expose the Micro-USB console (CP210x); PuTTY: `115200 8N1`, no flow control.
3. Boot from the USB stick (F12), then:

   ```sh
   lsblk                                   # /dev/mmcblk0 is the eMMC
   mkdir -p /mnt/usb && mount /dev/sdbX /mnt/usb
   gzip -dc /mnt/usb/edge610-*.img.gz | dd of=/dev/mmcblk0 bs=4M conv=fsync
   sync
   ```

4. Remove the USB stick and `reboot`. On first boot `zzz98-edge610-resize` grows the rootfs to the whole disk;
   `df -h /` should show ~14.3G (log: `logread -e edge610-resize`).

## Post-flash checks

On the serial console:

```sh
ip link                     # lan1..lan6 present (+ lo and the ethX ports)
logread -e edge610          # watchdog cleared, conduit, port-up messages
df -h /                     # ~14.3G when booted from eMMC (first-boot growth)
sensors                     # Core 0 / Core 1 temperatures (kmod-hwmon-coretemp)
/etc/openhsalc/core/hsalc_meta -v   # must print Mihomo Meta ... linux amd64 (amd64-v1)
```

- Idle for ≥10 minutes without a reboot → the watchdog is really off.
- Plug a cable into **LAN1** and open `http://192.168.1.1` → LuCI.
- Services → OpenHsalc: load a subscription and start the proxy.

## Build-time pitfalls

The full debug timeline (evidence, serial logs, build times) is in [`docs/bringup-log.en.md`](docs/bringup-log.en.md).

| Pitfall | Symptom | Fix |
| --- | --- | --- |
| BIOS hides P2SB (`8086:19dd` missing from `lspci`) | module silently returns `-ENODEV`, `ixgbe` never loads, only `lo` exists | the module derives the BAR from `/proc/iomem` (`INTC3000:00`, `0xFD000000` here); override with `p2sb_bar_addr=` |
| uci section names reject `-` | `uci: Parse error (invalid character in name field)`, bridge not applied | anonymous `config device` + `option name 'br-lan'` (asserted at build time) |
| `make download` has no overall timeout | half-dead connections hang forever, the build looks stuck | `CURL_OPTIONS=--max-time 600 --speed-time 60 --speed-limit 1024` + retries |

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| `ip link` shows no `lan1..lan6` | check `logread -e edge610` for `edge610_switch_standalone` / `edge610_dsa` errors; `dmesg \| grep -i -E 'dsa\|mv88e'`; `lsmod \| grep -E 'edge610\|mv88e\|dsa'` |
| `P2SB BAR unavailable` in the log | this BIOS hides P2SB (`8086:19dd` is not in `lspci`). The module derives the BAR from `/proc/iomem` (`INTC3000:00`, usually `0xfd000000`); if that fails, pass it manually: `modprobe edge610_switch_standalone p2sb_bar_addr=0xfd000000 ...` and `modprobe edge610_dsa conduit_name=ethX p2sb_bar_addr=0xfd000000` |
| Reboots every 4–5 minutes | watchdog still armed: `logread -e edge610` should not contain `iSMT SMBus adapter not found`. Check manually: `modprobe i2c-ismt; grep . /sys/bus/i2c/devices/*/name`, then `i2cset -y <bus> 0x22 0 0 b` |
| Mihomo prints `Illegal instruction` | the core was replaced with a v2/v3 (AVX) build. Only `linux-amd64-v1` works; put it back at `/etc/openhsalc/core/hsalc_meta` |
| No WAN / want a different WAN port | `lan6` is the WAN by default (DHCP client); `br-lan` only contains `lan1..lan5`, and `eth2`/`eth3` (SFP) stay unconfigured. To move it: LuCI → Network → Interfaces, change the `wan` device to `lanN` / `eth2` / `eth3` (the `conduit:` port from `logread -e edge610` is the switch uplink — **never** assign it an address) |
| More `ethX` ports than expected | X553 has four MACs and the enumerated count depends on the BIOS; trust the `conduit:` line and the physical cabling |

## Modifying and rebuilding

- To change the image: edit `package/edge610-board/` or the `.config` seed in the workflow → commit/push → re-run Actions.
- Key packages in the `.config` seed are asserted at build time (grep after defconfig); a missing package fails the build instead of producing a wrong image.
- Final checks: the image exists and has a sane size, the manifest contains the key packages, the rootfs contains the modules and scripts, and `hsalc_meta` is executable and prints Mihomo.
