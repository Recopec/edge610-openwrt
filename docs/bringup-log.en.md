# Edge 610 firmware bring-up log

> Chinese version: [bringup-log.md](bringup-log.md)

The complete path from the hand-off document to an end-to-end working device:
key findings and evidence, kept for future maintainers. All times are UTC, 2026-11-07 / 11-08.

---

## Phase 0 — Hand-off document (ImageBuilder route)

The hand-off document proposed GitHub Actions + OpenWrt **ImageBuilder** (23.05.5) to get:
6×RJ45 (Marvell DSA) + 2×SFP (X553), hardware watchdog disabled, OpenHsalc + mihomo `amd64-v1`
built in, a 1024 MB root partition, and the image flashed to the 16 GB eMMC.

The repository's first workflow used ImageBuilder. The build "succeeded" but the artifact was unusable.

## Phase 1 — Disproving the ImageBuilder route

Investigation (official feed index, 25.12 kernel Kconfig, CVMagic sources) confirmed:

| Problem | Evidence |
| --- | --- |
| Prebuilt x86 kernel has no DSA | The 23.05.5 x86 target `Packages` has no `kmod-dsa*`; `generic/config` contains `# CONFIG_NET_DSA is not set` |
| No `i2c-ismt` package | The watchdog bus (iSMT SMBus) driver is not enabled on x86, and there is no official kmod package |
| Phantom package names | `kmod-switch-mv88e6xxx` from the hand-off does not exist; the real name is `kmod-dsa-mv88e6xxx` |
| Out-of-tree modules cannot be built | This board needs CVMagic's `edge610_switch_standalone` + `edge610_dsa`, and ImageBuilder has no kernel build environment |

Conclusion: **the ImageBuilder route cannot satisfy the acceptance checklist** — switch to a full source build.

## Phase 2 — Full source build (OpenWrt 25.12.6)

New local package `package/edge610-board`:

- `src/edge610_switch_standalone.c`, `src/edge610_dsa.c` (CVMagic, GPL-2.0; port names `ge1..ge6` → `lan1..lan6`)
- `KernelPackage/edge610-switch`, `edge610-dsa` (**no AUTOLOAD**; the init script loads them in order)
- `KernelPackage/i2c-ismt` (`KCONFIG:=CONFIG_I2C_ISMT`, AUTOLOAD 52)
- `/etc/init.d/edge610` (START=19): disable watchdog → `edge610_switch_standalone` (with board parameters) → `ixgbe` → `mv88e6xxx` → `edge610_dsa`
- `/etc/uci-defaults/zzz99-edge610-network`: first boot writes `br-lan = lan1..lan6` @192.168.1.1
- The build strips `ixgbe`'s `AutoLoad,35` so probe order is fully controlled by the init script

## Phase 3 — First CI success, verification step misjudged

- run `42362985831`: `make` succeeded, produced an image (53.6 MB), manifest and rootfs tar
- But the verification step assumed `build_dir/.../root-x86_64` exists → failed (the directory name differed)
- Changed to **path-independent** checks: assert packages in the manifest, find modules with `find build_dir -path '*/lib/modules/*'`, check files inside the rootfs tar and run `hsalc_meta`

## Phase 4 — Plugins and toolchain polish

- run `42432099874`: all green, 60.1 MB artifact
- Baked in Chinese LuCI, `luci-app-ttyd`, `package-manager`, `statistics`, `ddns`, `sqm`, `wireguard`, diagnostic tools (ethtool-full/tcpdump/htop/mtr/iperf3/iftop/bind-host/nano/pciutils/usbutils/lm-sensors/block-mount), USB NIC/storage kmods
- CI now uses `actions/cache` for `dl/`
- Added `scripts/build-local.sh` (same source as CI, local build)

## Phase 5 — Local VM build (16 cores, 76 minutes)

| Item | Value |
| --- | --- |
| Environment | Ubuntu 24.04.5 LTS, 16 vCPU / 15 GiB / 196 GB ext4 |
| Full build | 02:20 → 03:36 (**76 minutes**); ~3.5 hours on 4-core CI |
| Incremental rebuild | **2–3 minutes** after a package change |

**Download issue diagnosed** (user reported "stuck at make download"):

- Proxy was fine (Cloudflare 5 MB/s single stream, 15 MB/s with 8 connections)
- `sources.cdn.openwrt.org` ~300 KB/s per connection (same direct or proxied — CDN per-connection limit); aggregate with concurrency reached 22 MB/s
- Real culprit: `make download`'s `curl` had **no overall timeout**, so half-dead connections hung forever; `mirror2.openwrt.org` was a 404 dead link
- Fix: `download.pl` supports `CURL_OPTIONS` → `--max-time 600 --speed-time 60 --speed-limit 1024`, plus 3 retries

## Phase 6 — First boot on hardware: watchdog OK, no network at all

First boot over serial (115200, CP210x):

```
edge610: watchdog: cleared register at 0x22 (bus 0)     <- watchdog cleared
edge610: watchdog: cleared register at 0x24 (bus 0)
modprobe: - edge610_switch_standalone
edge610: ERROR: edge610_switch_standalone failed to load
```

`ip link` showed only `lo`; `dmesg` had no dsa/mv88e/ixgbe output.

Diagnosis: `lspci -nn` showed this unit (DMI `Dell EMC EDGE610VWL`, BIOS 3.43.0.9-12) has
**no `8086:19dd`** and the whole `00:1f.1` function is missing (`setpci` says "No devices selected")
— **the BIOS hides P2SB**. CVMagic's units have it visible, so upstream code calling
`pci_get_device(19dd)` silently returned `-ENODEV`.

## Phase 7 — Solving the hidden P2SB (key breakthrough)

`/proc/iomem` leaked the address:

```
fdc20000-fdc2ffff : INTC3000:00
fdc50000-fdc5ffff : INTC3000:00
```

`fdc20000` is exactly `P2SB_BAR + 0xC20000` (the module's `NORTH_OFFSET`) → **P2SB BAR = 0xFD000000**.

Both modules now use a three-level fallback:

1. `pci_get_device(8086:19dd)` (units like CVMagic's)
2. Module parameter `p2sb_bar_addr=`
3. Walk `iomem_resource`, match `INTC3000*` with size `0x10000` and offset `0xC20000` → derive the BAR

Also confirmed the kernel **never uses** `dsa_chip_data.host_dev`
(`grep -rn host_dev drivers/net/dsa/` returns nothing), so when P2SB is invisible it is enough to
fall back to the conduit netdev's device.

**Direct module injection over serial** (no reflash): the stripped `.ko` from the image was written
to the device as base64 over the serial console (the device has no `base64`/`od`/`xxd`, but the
`ruby` pulled in by OpenHsalc can decode with `String#unpack1("m")`), md5-checked, then `insmod`:

```
edge610-switch: P2SB hidden by BIOS, BAR 0x00000000fd000000 from iomem
edge610-switch: Marvell 88E6190 rev 1 at P2SB BAR 0x00000000fd000000
edge610-switch: X553 NW_MNG_IF_SEL 0x00102002 -> 0x02082002
edge610-switch: cpu10 status=0x0e4a link=up
```

## Phase 8 — uci config syntax bug

After all modules loaded, `lan1..lan6` appeared, but `uci show network` reported:

```
uci: Parse error (invalid character in name field) at line 10
```

Cause: uci section names may not contain `-`; `config device 'br-lan'` is invalid. The correct
form is an anonymous `config device` plus `option name 'br-lan'` (standard OpenWrt style).

After the fix:

```
uci get network.lan.ipaddr -> 192.168.1.1
br-lan: port 1..6(lan1..lan6) entered blocking state
br-lan  UP  192.168.1.1/24  fd65:6afb:6a3f::1/60
```

End-to-end path working (`NO-CARRIER` only because no cable was plugged in).

CI and local builds now have a regression assertion: a quoted section name in uci-defaults fails the build.

---

## Hardware facts (measured)

| Item | Value |
| --- | --- |
| DMI | `Dell EMC EDGE610VWL/EDGE610VWL-CPU`, BIOS `3.43.0.9-12 09/02/2020` |
| P2SB | `8086:19dd` **hidden** (not in lspci); BAR `0xFD000000`; iomem alias `INTC3000:00` |
| iSMT SMBus | `00:12.0 [8086:19ac]` → watchdog at bus 0, `0x22`/`0x24` |
| X553 | `03:00.0/.1`, `05:00.0/.1` (`8086:15c3`), MACs `18:5a:58:c0:f0:e0..e3` |
| conduit | `eth0` (PCI `0000:03:00.0`, lowest MAC) |
| Switch | Marvell 88E6190 rev 1, CPU port 10, 2.5G SGMII |
| Other | `02:00.0` QCA986x/988x WiFi card (disabled in this firmware); `00:13.0` SATA, `00:1c.0` SD, `00:15.0` xHCI |

## Build artifacts comparison

| Build | Duration | Image size | sha256 |
| --- | --- | --- | --- |
| CI (4 cores) | ~3.5 h | 60,103,685 B | `994383d4…` |
| Local VM (16 cores) | 76 min | 61,120,509 B | `ad84c0f0…` |
| + P2SB fix | incremental | 61,149,629 B | `4c9ed17d…` |
| + uci fix | incremental 2 min | 61,149,795 B | `87b79c87…` |

(Size differences between CI and local builds come from compression; the package set is identical: 319 packages.)

## Troubleshooting notes

- The serial console can be bridged to TCP with `scripts/serial-bridge.ps1` (default `:7001`) for remote driving
- The device has no `base64`/`od`/`xxd`/`python`, but it does have `ruby` (`unpack1("m")` decodes base64)
- `/lib/modules/<ver>/` has no `modules.dep`, yet `modprobe <name>` still works (ubox kmodloader)
- Log prefixes: `edge610-switch:` / `edge610-dsa:` / `mv88e6085 sw0:00`

## 2026-11-08 BIOS survey + hardware capability confirmation

Drove the BIOS (AMI Aptio 5.13, `3.43.0.9-12`) over serial for a read-only survey; no setting was
changed (`Exit Without Saving`).

| Observation | Result |
| --- | --- |
| CPU | `Intel(R) Atom(TM) CPU C3308 @ 1.60GHz` (the earlier C3338 in the hand-off was wrong) |
| Memory | 4,003,672 kB (≈3.8 GiB) |
| BIOS NIC page | Four `X553 Backplane` entries, `Chip Type` = **X550**, `PCI Device ID` = **15C3** |
| Speed options | Only `Link Speed [Auto Negotiated]`; **no manual 2.5G/10G option** |
| SFP ports | `05:00.0/.1` (`eth2`/`eth3`) show `Link Status [Disconnected]` (no modules inserted) |
| Serial keyboard mapping | `Down` = `ESC[B`, `Right` = `ESC[C`; `Up` = `ESC[A` does not work inside submenus (`ESC[1A`/`ESC OA` are treated as `Esc`) |

**SFP speed conclusion**: the `ethtool` capability table tops out at `2500baseT/Full` (SGMII mode)
or `1000baseKX/Full`; there is no `10000base*`, and the BIOS has no 10G option → **these two cages
are 1G/2.5G max, no 10G**. A 1.25G module = 1G SFP (8b/10b, 1.25 Gbps line rate) and works directly.

**SFP port mapping**: the two ports of the second X553 controller (`05:00.0`/`05:00.1` = `eth2`/`eth3`)
are the two SFP cages; `03:00.0` (`eth0`) is the switch conduit and `03:00.1` (`eth1`) is idle.
The default WAN is `lan6` (see the 2026-11-11 entry); both SFP cages ship as LAN bridge members.

**eMMC state**: `mmcblk0` 14.6 GiB; `p1` 128 MB (EFI) + `p2` 2 GB (a diag-os the user installed,
605 MB used), the rest unused. After flashing this firmware, `p2` is grown to the whole disk on first boot.

## 2026-11-08 Firmware hardening

| Item | Implementation |
| --- | --- |
| SFP WAN | `zzz99-edge610-network` adds `wan`=eth2 (DHCP), `wan2`=eth3 (none) |
| eMMC growth | New `zzz98-edge610-resize` (`sfdisk -N 2` keeping the start sector → `partx -u` → `resize2fs`); CI verifies growth and idempotence on a loop device |
| Temperature | `kmod-coretemp` (Denverton MSR) + existing `lm-sensors` |
| WiFi | `kmod-ath10k` + `ath10k-firmware-qca988x` (`168c:003c`) |
| Dependencies | Board package DEPENDS gains `sfdisk`, `resize2fs` |

## kmodloader drops module parameters (2026-11-09)

**Symptom**: `lan1..lan6` all missing; `dmesg` says
`edge610-dsa: conduit eno1 is not available; load this module after ixgbe`,
even though `/etc/init.d/edge610` ran `modprobe ixgbe` in order and passed `conduit_name=eth0`.

**Root cause**: OpenWrt's `/sbin/modprobe` is a symlink to `kmodloader`, which **silently ignores
`name=value` parameters**. Evidence: after `edge610_switch_standalone` loaded,
`/sys/module/.../parameters/` showed `x553_sgmii=N`, `serdes_autoneg=N`, `cpu_mac_ctl=12351` —
all defaults instead of the `1/1/0x203e` the script passed.

**Fix**: `/etc/init.d/edge610` now uses `insmod /lib/modules/$(uname -r)/<mod>.ko <params>`, so
parameters go straight to the kernel; `mv88e6xxx` is still preloaded with `modprobe` (insmod does not
process softdeps). Measured: `insmod edge610_dsa.ko conduit_name=eth0` makes DSA register `lan1-lan6`.

## The CPU link is port 9 ↔ eth1, not port 10 ↔ eth0 (2026-11-09)

The 88E6190 has two CPU ports wired to the two functions of the X553 controller at `0000:03:`:

| Switch CPU port | X553 function | netdev |
| --- | --- | --- |
| 10 | 0000:03:00.0 | eth0 |
| 9 | 0000:03:00.1 | eth1 |

On this unit only **port 9 ↔ eth1** comes up (`NIC Link is Up 1 Gbps`); port 10 ↔ eth0 stays
`NO-CARRIER`. With port 10 the switch saw the PC's broadcast frames, but they never reached the
CPU — which looks like "DHCP gets no address".

Fix (implemented):

1. `edge610_switch_standalone` supports `cpu_port=0`: switch both X553 functions to SGMII and put
   both ports 9/10 into forwarding state;
2. `edge610_dsa` gains a `cpu_port` parameter (default 10);
3. `/etc/init.d/edge610` polls the `eth0`/`eth1` carrier after ixgbe loads and uses **the pair that
   actually came up** as the conduit and DSA CPU port.

## Writing the eMMC correctly (2026-11-09)

**Do not** copy the whole USB device with `dd if=/dev/sdb of=/dev/mmcblk0`. Imaging tools
(Rufus/Etcher) extend the GPT `last-lba` to the USB stick size (e.g. 119 GB); copied onto the
14.6 GB eMMC, the kernel rejects the whole partition table because `last_usable_lba` exceeds the
device, and boot hangs at `Waiting for root device PARTUUID=...`.

Correct approach (put the .img.gz on another partition of the stick, or another stick):

```sh
gzip -dc /mnt/usb/edge610-YYYYMMDD-HHMM.img.gz | dd of=/dev/mmcblk0 bs=4M
sync
```

This writes the image's own GPT (1.09 GB layout), which is valid for the 14.6 GB eMMC; on first boot
`zzz98-edge610-resize` grows p2 to the whole disk.

If you already copied the whole device, you can fix only the partition table (data untouched):

```sh
sfdisk -d /dev/sdb > /tmp/pt.dump
LAST=$(( $(cat /sys/block/mmcblk0/size) - 34 ))
sed -i "s|^last-lba: .*|last-lba: $LAST|; s|^device: .*|device: /dev/mmcblk0|" /tmp/pt.dump
sfdisk /dev/mmcblk0 < /tmp/pt.dump
```

Verify: `lsblk` should show `mmcblk0p1/p2/p3` and `mount -o ro /dev/mmcblk0p2 /mnt` should succeed.


## 2026-11-11 default WAN and the modem watchdog

| Item | Implementation |
| --- | --- |
| Default WAN | `zzz99-edge610-network` takes `lan6` out of the LAN bridge and makes it `wan` (DHCP client); `br-lan` carries `lan1..lan5` plus both SFP cages (`eth3`/`eth2`) |
| Egress order | `wan` (lan6, metric 0) first; `wwan` (LTE, metric 100) only takes over when the former has no default route - route-metric takeover, no health checks |
| Keeping config | The script skips everything when `network.lan` already exists, so a keep-settings sysupgrade is no longer reset to 192.168.1.1 |
| Modem watchdog | `modem-wan-watch` reads the slot-1 card state every 60 s; two consecutive non-`present` readings trigger `ifdown wwan` + `AT!CFUN=1,1` (10 min throttle); `ifup wwan` once the card is readable again |
| First-boot interface | New `zzz99-edge610-network-modem`: creates `network.wwan` (qmi, `apn cmnet`, `ipv4v6`, metric 100, auto) and puts `wwan` into the `wan` firewall zone |

## 2026-11-11 SFP port bring-up

| Item | Result |
| --- | --- |
| Port mapping | With a module in SFP1 only `05:00.1` (`eth3`) returns module EEPROM, so **SFP1 = `eth3`** and SFP2 = `eth2` (`05:00.0`) |
| Modules | Copper SFPs: `OEM` / `OYJ-SFP-T` rev A, 1.25G, serial `82608030053` (SFP1) / `82608150004` (SFP2), dated 2026-11-04 |
| Link | With a cable attached: `ixgbe 0000:05:00.1 eth3: NIC Link is Up 1 Gbps, Flow Control: RX/TX`, full duplex, `rx_errors`/`rx_crc_errors` both 0. After `ip link set up` the module PHY needs ~2 s, so the first event is an `Up -> Down` pair |
| Port mode | ixgbe reports `Supported link modes: 1000baseKX/Full`: the host side is fixed 1G SGMII/backplane, 10/100M is negotiated by the module's own PHY |
| DDM | Both modules return byte-identical A2 pages (temp 19.8 degC, Vcc 3.31 V, fixed Tx/Rx values) - a copper part has no optics, so these are placeholders. A2 `0x0180` onwards is all zeroes, no copper PHY register map -> useless for monitoring |
| Default network | `zzz99-edge610-network` now puts `lan1..lan5` + `eth3` + `eth2` into `br-lan`: both SFP cages are LAN ports by default and work as soon as a cable is plugged in; `lan6` stays the WAN |
| Module info | The image ships `ethtool-full` (not the default tiny variant): `ethtool -m eth3` decodes the A0 page (`Identifier`/`Vendor name`/`Vendor PN`/`Serial number`); the tiny variant is built with `--disable-pretty-dump` and prints hex only |

## 2026-11-11 Flashing the image: a 16M boot partition cannot hold the config backup

Flashing the repo's image onto the first real device with `sysupgrade` (keep config) left the **root password empty**: dropbear rejected logins (`User 'root' has blank password, rejected`), LuCI showed the "set a password" page and the serial console printed `There is no root password defined on this device!`. The network config itself was restored correctly (`lan` still 10.1.2.3 with `gateway 10.1.2.1`, `br-lan` ports include `eth2/eth3`).

Cause: sysupgrade writes the config backup to p1 (`/boot`, vfat), which the image sizes at **16 MB**, leaving 9.5 MB after kernel+grub. A backup that includes openclash is **10.5 MB** (the 16 MB `etc/openclash/core/clash_meta` and 10 MB `GeoSite.dat` dominate even compressed). The backup does not fit, so the restore unpacks only the first part of the tar; `/etc/shadow` comes after the `/etc/config` entries, so the password is lost while the config survives.

Fix: add `CONFIG_TARGET_KERNEL_PARTSIZE=64` to the image seed config (boot partition 16 -> 64 MB, ~57 MB free). The rootfs partition shrinks by 48 MB, but `zzz98-edge610-resize` grows it to the whole disk on first boot, so nothing is lost; existing devices see a partition-table change and sysupgrade falls back to a full-disk write by itself.

Note: before upgrading, run `sysupgrade -b backup.tar.gz` manually and copy it off the device, in case a backup gets truncated the same way.

## 2026-11-11 Boot-time sh error: Intel microcode was missing

Every boot printed `sh: write error: Invalid argument` on the console. It comes from OpenWrt's x86 `/lib/preinit/02_load_x86_ucode`:

```sh
if [ -e "/sys/devices/system/cpu/microcode/reload" ]; then
	echo 1 > /sys/devices/system/cpu/microcode/reload
fi
```

The kernel builds with `CONFIG_MICROCODE_LATE_LOADING=y` and `CONFIG_MICROCODE_LATE_FORCE_MINREV=y`, but the image shipped no `/lib/firmware/intel-ucode/`, so writing `reload` returns `EINVAL` (reproduced by hand: `rc=1`) and busybox sh prints that error. The side effect is worse than the message: `dmesg` reports `Register File Data Sampling: Vulnerable: No microcode` and the CPU stays at its factory revision `0x0000002e`.

Fix: ship `CONFIG_PACKAGE_intel-microcode=y` (in-tree `package/firmware/intel-microcode`, 20251111, installs `/lib/firmware/intel-ucode/`), so the preinit reload succeeds, the message disappears and the CPU gets its microcode (RFDS et al. mitigated).

Also raised the boot partition from 64 MB to **128 MB** (`CONFIG_TARGET_KERNEL_PARTSIZE=128`, matching the upstream armsr default) so the config backup keeps headroom as openclash rules grow.

## 2026-11-12 A clean install (sysupgrade -n) exposed a first-boot network bug

After a clean flash `br-lan` held only `eth0` and there was no `wan`: `zzz99-edge610-network` treated "network.lan exists" as "the user already configured it", but board.d's `99-default_network` creates `lan=br-lan(eth0)` before the script runs, so it exited early and neither the six RJ45 ports nor the two SFP cages were bridged (eth0 is the DSA conduit, bridging it is worse than useless).

Fix: decide on the pristine factory state instead - only a non-192.168.1.1 `lan.ipaddr` or a `lan.gateway` counts as user configuration (and then `/etc/edge610-network-applied` is written so later upgrades skip the script). Otherwise edit only what the board owns: replace the br-lan ports with `lan1..lan5 + eth3 + eth2`, point `lan` at `br-lan`, and add `wan=lan6(dhcp)` when no wan interface exists, leaving interfaces other packages added (`docker`, `wwan`) untouched.

## 2026-11-12 Preset root password on factory installs

A fresh install has no root password, dropbear refuses blank-password logins, so the only way in was the serial console. The image now ships `zzz99-edge610-password`: it writes the sha256-crypt hash of `edge610pass` only when root's hash in `/etc/shadow` is empty, so a keep-config upgrade (root already hashed) never fires it. Changing the password with `passwd` afterwards makes the script stop matching.

### Fix: the factory-default check missed `192.168.1.1/24`

The first version compared `[ "$ipaddr" != "192.168.1.1" ]`, but current OpenWrt board.d writes `list ipaddr '192.168.1.1/24'`, so `uci get` returns `192.168.1.1/24` and the factory config looked user-modified - the script exited again (`br-lan` with only `eth0`). Use a `case` that accepts both spellings.

Also bumped `PKG_RELEASE` to 2: the package build keyed off directory mtimes, so the freshly added `zzz99-edge610-password` never made it into the cached apk and a clean flash still had an empty root password.

## 2026-11-12 The switch module stopped finding the P2SB BAR

Symptom: after one boot `/sys/class/net` only had `lo/docker0/wwan0` - all six RJ45 ports and both SFP cages were gone, and dmesg said

```
edge610-switch: P2SB BAR unavailable (device hidden by BIOS and no iomem hint); pass p2sb_bar_addr=
insmod: failed to insert .../edge610_switch_standalone.ko
```

Cause: the module only scanned `iomem_resource.child` (depth 1) for a resource named `INTC3000`, size `0x10000`, whose `start - 0xc20000` is 16 MB aligned. On this boot the firmware nested that window one level deeper, under a PCI host bridge window:

```
fdc20000-fdc2ffff : INTC3000:00          <- actually at depth 2
```

so the scan came back empty, the module returned -ENODEV, the init script aborted and even `ixgbe` never loaded.

Verified by hand: `insmod edge610_switch_standalone.ko p2sb_bar_addr=0xfd000000` succeeds immediately (`north window ... padbar=0x400`, `88E6190 rev 1`, `cpu10 link=up`), so the BAR value itself is unchanged.

Fix: make `p2sb_bar_from_iomem()` walk the resource tree recursively in both modules.
