#!/bin/bash
# Local mirror of .github/workflows/build.yml for the Edge 610 image.
# Idempotent: re-running reuses clone/feeds/config and rebuilds incrementally
# (first run builds rustc+toolchain, later runs typically finish in minutes).
#
# Usage:
#   PROXY=http://192.168.68.1:7897 ./build-local.sh
#
# Requirements: Ubuntu 24.04 x86_64, >=8 cores, >=16GB RAM, >=60GB free disk.
set -euo pipefail

WORK="${WORK:-$HOME/work}"
PROXY="${PROXY:-}"

if [ -n "$PROXY" ]; then
  export http_proxy="$PROXY" https_proxy="$PROXY" HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY"
  export no_proxy=localhost,127.0.0.1,192.168.0.0/16
fi
# download.pl honours CURL_OPTIONS: cap per-file time and abort stalled transfers.
export CURL_OPTIONS="--max-time 600 --speed-time 60 --speed-limit 1024"

REPO="$WORK/edge610-openwrt"
OW="$WORK/openwrt"
mkdir -p "$WORK"

log() { echo "=== $(date -u +%H:%M:%S) $* ==="; }

# 1. Sources ----------------------------------------------------------------
if [ ! -d "$REPO/.git" ]; then
  log "clone repo"
  rm -rf "$REPO"
  git clone https://github.com/Recopec/edge610-openwrt.git "$REPO"
else
  log "update repo"
  git -C "$REPO" pull --ff-only || true
fi

if [ ! -d "$OW/.git" ]; then
  log "clone openwrt v25.12.6"
  rm -rf "$OW"
  git clone --depth 1 --branch v25.12.6 https://github.com/openwrt/openwrt.git "$OW"
fi

cd "$OW"

# 1b. Patch OpenWrt's ext4 image builder --------------------------------
# make_ext4fs writes a resize inode the kernel refuses to grow online
# (openwrt/openwrt#7729); mke2fs produces a filesystem that resizes.
if grep -q 'make_ext4fs' include/image.mk 2>/dev/null; then
  log "patch include/image.mk (mkfs.ext4)"
  git apply "$REPO/patches/openwrt/0001-image-mkfs-ext4-use-mke2fs.patch" \
    || { echo "image.mk patch failed"; exit 1; }
fi
! grep -q 'make_ext4fs' include/image.mk || { echo "make_ext4fs still present"; exit 1; }

# 1c. EM7565 (1199:9091) is missing from option's device table; without it
# the modem exposes no AT ports (qmi_wwan still works).
cp "$REPO/patches/openwrt/0002-usb-serial-option-add-em7565.patch" \
  target/linux/x86/patches-6.12/999-usb-serial-option-em7565.patch

log "sync edge610-board package"
rm -rf "$OW/package/edge610-board"
cp -r "$REPO/package/edge610-board" "$OW/package/"

cd "$OW"

# 2. Feeds ------------------------------------------------------------------
if [ ! -f feeds.conf ]; then
  log "configure feeds"
  curl -fsSL -o feeds.conf \
    https://downloads.openwrt.org/releases/25.12.6/packages/x86_64/feeds.conf
  sed -i '/^src-git base /d' feeds.conf
  OC_TAG="$(curl -fsSL https://api.github.com/repos/vernesong/OpenClash/releases/latest \
    | jq -r '.tag_name // empty' || true)"
  [ -n "$OC_TAG" ] || OC_TAG=master
  echo "src-git openclash https://github.com/vernesong/OpenClash.git;${OC_TAG}" >> feeds.conf
  echo "src-git istore https://github.com/istoreos/istore;main" >> feeds.conf

  cat feeds.conf
fi
if [ ! -d feeds/luci ]; then
  log "feeds update/install"
  ./scripts/feeds update -a
  ./scripts/feeds install -a
fi
# iStore feed (may be new on an existing tree)
if ! grep -q "src-git istore" feeds.conf; then
  echo "src-git istore https://github.com/istoreos/istore;main" >> feeds.conf
fi
if [ ! -d feeds/istore ]; then
  log "feeds update/install istore"
  ./scripts/feeds update istore
  ./scripts/feeds install -a -p istore
fi

# Argon theme: clone into package/ (its root Makefile breaks the feed scanner)
if [ ! -f package/luci-theme-argon/Makefile ]; then
  log "fetch argon theme"
  rm -rf package/luci-theme-argon
  git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
fi

# 3. po2lmo host tool -------------------------------------------------------
if [ ! -x staging_dir/host/bin/po2lmo ]; then
  log "build po2lmo"
  make -C package/feeds/luci/luci-base/src po2lmo
  mkdir -p staging_dir/host/bin
  cp package/feeds/luci/luci-base/src/po2lmo staging_dir/host/bin/po2lmo
fi

# 4. Mihomo core ------------------------------------------------------------
CORE="$OW/package/edge610-board/files/etc/openclash/core/clash_meta"
CACHE="$WORK/clash_meta.cache"
if [ ! -s "$CORE" ] && [ -s "$CACHE" ]; then
  log "restore mihomo core from cache"
  mkdir -p "$(dirname "$CORE")"
  cp "$CACHE" "$CORE"
  chmod 755 "$CORE"
fi
if [ ! -s "$CORE" ]; then
  log "download mihomo amd64-v1"
  mkdir -p "$(dirname "$CORE")"
  CORE_URL="$(curl -fsSL https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
    | jq -r '.assets[] | select(.name | contains("linux-amd64-v1") and (endswith(".gz"))) | .browser_download_url' \
    | head -n1 || true)"
  [ -n "$CORE_URL" ] || CORE_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/mihomo-linux-amd64-v1-go120-v1.19.33.gz"
  echo "core: $CORE_URL"
  echo "$CORE_URL" | grep -q "linux-amd64-v1"
  for attempt in 1 2 3 4; do
    curl -fL --retry 5 --retry-delay 3 -o /tmp/mihomo.gz "$CORE_URL" && break
    log "mihomo download failed (attempt $attempt), retrying"
    sleep 5
  done
  [ -s /tmp/mihomo.gz ] || { echo "mihomo download failed after retries"; exit 1; }
  gzip -dc /tmp/mihomo.gz > "$CORE"
  chmod 755 "$CORE"
  cp "$CORE" "$CACHE" 2>/dev/null || true
  "$CORE" -v
fi

# 5. Config seed ------------------------------------------------------------
# The seed is merged into an existing .config instead of only being written
# on the first run: incremental trees pick up newly added packages too.
cat > /tmp/edge610-seed.config <<'EOF'
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_MULTI_PROFILE=y
CONFIG_TARGET_DEVICE_x86_64_DEVICE_generic=y
CONFIG_TARGET_ROOTFS_PARTSIZE=1024
CONFIG_TARGET_KERNEL_PARTSIZE=128
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_GRUB_IMAGES=y
CONFIG_GRUB_EFI_IMAGES=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_edge610-board=y
CONFIG_PACKAGE_kmod-edge610-switch=y
CONFIG_PACKAGE_kmod-edge610-dsa=y
CONFIG_PACKAGE_kmod-i2c-ismt=y
CONFIG_PACKAGE_kmod-dsa=y
CONFIG_PACKAGE_kmod-dsa-mv88e6xxx=y
CONFIG_PACKAGE_kmod-ixgbe=y
CONFIG_PACKAGE_i2c-tools=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_coreutils=y
CONFIG_PACKAGE_coreutils-nohup=y
CONFIG_PACKAGE_kmod-nft-tproxy=y
CONFIG_PACKAGE_ca-certificates=y
CONFIG_PACKAGE_dnsmasq-full=y
# CONFIG_PACKAGE_dnsmasq is not set
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_luci-app-package-manager=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_luci-app-statistics=y
CONFIG_PACKAGE_luci-app-ddns=y
CONFIG_PACKAGE_luci-app-sqm=y
CONFIG_PACKAGE_luci-proto-wireguard=y
CONFIG_PACKAGE_luci-proto-ipv6=y
CONFIG_PACKAGE_luci-proto-qmi=y
# LuCI i18n packages are HIDDEN with DEFAULT:=LUCI_LANG_<lang>: selecting the
# language symbol is the only way to pull them in (per-package symbols are
# ignored by defconfig). The po dir is zh_Hans, the package name keeps the
# legacy alias zh-cn.
CONFIG_LUCI_LANG_zh_Hans=y
# ethtool-full, not the default "tiny" variant: tiny is built with
# --disable-pretty-dump, which strips the SFF-8472 decoder and makes
# "ethtool -m" print raw hex only.
CONFIG_PACKAGE_ethtool-full=y
CONFIG_PACKAGE_intel-microcode=y
# CONFIG_PACKAGE_ethtool is not set
CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_mtr=y
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_iftop=y
CONFIG_PACKAGE_bind-host=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_pciutils=y
CONFIG_PACKAGE_usbutils=y
CONFIG_PACKAGE_lm-sensors=y
CONFIG_PACKAGE_kmod-hwmon-coretemp=y
CONFIG_PACKAGE_kmod-ath10k=y
CONFIG_PACKAGE_ath10k-firmware-qca988x=y
CONFIG_PACKAGE_wpad-basic-mbedtls=y
CONFIG_PACKAGE_block-mount=y
CONFIG_PACKAGE_kmod-usb-net-rtl8152=y
CONFIG_PACKAGE_kmod-usb-net-asix-ax88179=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ether=y
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-exfat=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-ntfs3=y
CONFIG_PACKAGE_kmod-usb-printer=y
# Onboard Sierra Wireless EM7565 LTE modem (AT + QMI)
CONFIG_PACKAGE_kmod-usb-serial=y
CONFIG_PACKAGE_kmod-usb-serial-wwan=y
CONFIG_PACKAGE_kmod-usb-serial-option=y
CONFIG_PACKAGE_kmod-usb-wdm=y
CONFIG_PACKAGE_kmod-usb-net-qmi-wwan=y
CONFIG_PACKAGE_uqmi=y
# qmicli: QMI NAS "get PLMN name" — the network (NITZ/MM info) operator name
CONFIG_PACKAGE_qmi-utils=y
CONFIG_PACKAGE_e2fsprogs=y
CONFIG_PACKAGE_smartmontools=y
CONFIG_PACKAGE_hdparm=y
CONFIG_PACKAGE_luci-app-chrony=y
CONFIG_PACKAGE_luci-app-librespeed=y
CONFIG_PACKAGE_luci-app-vnstat2=y
CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_luci-app-acme=y
CONFIG_PACKAGE_luci-app-uhttpd=y
CONFIG_PACKAGE_acme-acmesh=y
CONFIG_PACKAGE_luci-app-banip=y
CONFIG_PACKAGE_rsync=y
CONFIG_PACKAGE_nmap=y
CONFIG_PACKAGE_luci-app-acl=y
CONFIG_PACKAGE_luci-app-lxc=y
CONFIG_PACKAGE_lxc=y
CONFIG_PACKAGE_lxc-common=y
CONFIG_PACKAGE_lxc-templates=y
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_sysstat=y
CONFIG_PACKAGE_strace=y
CONFIG_PACKAGE_lsof=y
CONFIG_PACKAGE_arp-scan=y
CONFIG_PACKAGE_dockerd=y
CONFIG_PACKAGE_containerd=y
CONFIG_PACKAGE_runc=y
CONFIG_PACKAGE_tini=y
CONFIG_PACKAGE_docker=y
CONFIG_PACKAGE_docker-compose=y
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_PACKAGE_kmod-veth=y
CONFIG_PACKAGE_kmod-ipt-nat=y
CONFIG_PACKAGE_kmod-ipt-physdev=y
CONFIG_PACKAGE_kmod-nf-ipvs=y
CONFIG_PACKAGE_kmod-ipt-nat6=y
CONFIG_PACKAGE_iptables-nft=y
CONFIG_PACKAGE_iptables-mod-extra=y
CONFIG_PACKAGE_kmod-br-netfilter=y
CONFIG_PACKAGE_kmod-nf-conntrack-netlink=y
CONFIG_PACKAGE_kmod-tcp-bbr=y
CONFIG_PACKAGE_luci-app-wifischedule=y
CONFIG_PACKAGE_wireguard-tools=y
CONFIG_PACKAGE_luci-app-mwan3=y
CONFIG_PACKAGE_luci-app-pbr=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-app-nlbwmon=y
CONFIG_PACKAGE_luci-app-wol=y
CONFIG_PACKAGE_luci-app-udpxy=y
CONFIG_PACKAGE_luci-app-omcproxy=y
CONFIG_PACKAGE_luci-app-lldpd=y
CONFIG_PACKAGE_luci-app-ksmbd=y
CONFIG_PACKAGE_ksmbd-server=y
CONFIG_PACKAGE_luci-app-hd-idle=y
CONFIG_PACKAGE_luci-app-filebrowser=y
CONFIG_PACKAGE_luci-app-commands=y
CONFIG_PACKAGE_luci-app-irqbalance=y
CONFIG_PACKAGE_luci-app-p910nd=y
CONFIG_PACKAGE_luci-app-ser2net=y
CONFIG_PACKAGE_luci-app-filemanager=y
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-store=y
CONFIG_PACKAGE_luci-lib-taskd=y
CONFIG_PACKAGE_taskd=y
CONFIG_PACKAGE_xz-utils=y
CONFIG_PACKAGE_luci-compat=y
EOF
# The seed is the source of truth: if it changed, regenerate .config so that
# packages removed from the seed really disappear (defconfig never drops a
# symbol that is already selected).
SEED_HASH="$(sha256sum /tmp/edge610-seed.config | cut -d' ' -f1)"
if [ -f .config ] && [ "$(cat .config.seedhash 2>/dev/null)" = "$SEED_HASH" ]; then
  log "seed unchanged, keeping incremental .config"
else
  log "write .config from seed"
  rm -f .config
  cp /tmp/edge610-seed.config .config
  printf '%s\n' "$SEED_HASH" > .config.seedhash
fi
log "make defconfig"
make defconfig

for sym in \
  CONFIG_TARGET_x86_64=y \
  CONFIG_TARGET_ROOTFS_PARTSIZE=1024 \
  CONFIG_TARGET_KERNEL_PARTSIZE=128 \
  CONFIG_PACKAGE_edge610-board=y \
  CONFIG_PACKAGE_kmod-edge610-switch=y \
  CONFIG_PACKAGE_kmod-edge610-dsa=y \
  CONFIG_PACKAGE_kmod-i2c-ismt=y \
  CONFIG_PACKAGE_kmod-dsa-mv88e6xxx=y \
  CONFIG_PACKAGE_kmod-ixgbe=y \
  CONFIG_PACKAGE_luci-app-openclash=y \
  CONFIG_PACKAGE_i2c-tools=y \
  CONFIG_PACKAGE_ip-full=y \
  CONFIG_PACKAGE_dnsmasq-full=y \
  CONFIG_PACKAGE_luci-app-ttyd=y \
  CONFIG_PACKAGE_luci-app-package-manager=y \
  CONFIG_PACKAGE_luci-proto-wireguard=y \
  CONFIG_PACKAGE_ethtool-full=y \
  CONFIG_PACKAGE_intel-microcode=y \
  CONFIG_PACKAGE_iperf3=y \
  CONFIG_PACKAGE_kmod-hwmon-coretemp=y \
  CONFIG_PACKAGE_kmod-ath10k=y \
  CONFIG_PACKAGE_ath10k-firmware-qca988x=y \
  CONFIG_PACKAGE_wpad-basic-mbedtls=y \
  CONFIG_PACKAGE_sfdisk=y \
  CONFIG_PACKAGE_partx-utils=y \
  CONFIG_PACKAGE_resize2fs=y \
  CONFIG_PACKAGE_luci-theme-argon=y \
  CONFIG_PACKAGE_luci-app-store=y \
  CONFIG_PACKAGE_luci-app-ksmbd=y \
  CONFIG_LUCI_LANG_zh_Hans=y; do
  grep -q "^${sym}$" .config || { echo "MISSING after defconfig: $sym"; exit 1; }
done
grep -q '^# CONFIG_PACKAGE_dnsmasq is not set' .config || { echo "plain dnsmasq still enabled"; exit 1; }
grep -q '^# CONFIG_PACKAGE_ethtool is not set' .config || { echo "tiny ethtool still enabled"; exit 1; }

# 6. ixgbe autoload strip (probe order owned by /etc/init.d/edge610) --------
MK=package/kernel/linux/modules/netdevices.mk
if grep -q 'AutoLoad,35,ixgbe)' "$MK"; then
  log "strip ixgbe autoload"
  sed -i '/AutoLoad,35,ixgbe)/d' "$MK"
fi
! grep -q 'AutoLoad,35,ixgbe)' "$MK" || { echo "sed failed"; exit 1; }

# 7. Build ------------------------------------------------------------------
log "make download"
ok=0
for i in 1 2 3; do
  if timeout 2400 make download -j"$(nproc)" > dl.log 2>&1; then ok=1; break; fi
  echo "download attempt $i failed, retrying (cached files are kept)"
  pkill -f "curl -f --connect-timeout" || true
  sleep 3
done
[ "$ok" = 1 ] || { echo "download failed after 3 attempts"; tail -n 60 dl.log; exit 1; }

# luci-base intermittently fails when world builds it in parallel with the
# other LuCI packages (host/target staging race). Build it serially first so
# the parallel world run only reuses it.
log "pre-build luci-base"
make package/feeds/luci/luci-base/compile || { echo "luci-base pre-build failed"; exit 1; }

# luci-base races when the whole tree is built at full parallelism on a
# 16-vCPU/16GB runner; half the cores is stable and still fast.
JOBS=$(( $(nproc) / 2 ))
[ "$JOBS" -lt 4 ] && JOBS=4
# The package install step is stamp-based, so files/ changes are not picked up
# on an incremental tree. Clean it every run (seconds) so new uci-defaults and
# Lua views always land in the image.
log "clean edge610-board package"
make package/edge610-board/clean >/dev/null 2>&1 || true

log "make -j$JOBS"
make -j"$JOBS"

# 8. Verify -----------------------------------------------------------------
log "verify"
IMG="$(ls bin/targets/x86/64/*-generic-ext4-combined-efi.img.gz | head -n1)"
[ -n "$IMG" ] || { echo "EFI image missing"; exit 1; }
MAN=bin/targets/x86/64/openwrt-x86-64.manifest
TAR=bin/targets/x86/64/openwrt-x86-64-rootfs.tar.gz
for p in luci-app-openclash i2c-tools ip-full dnsmasq-full luci-app-ttyd \
         kmod-edge610-switch kmod-edge610-dsa kmod-i2c-ismt kmod-dsa-mv88e6xxx kmod-ixgbe \
         kmod-hwmon-coretemp kmod-ath10k ath10k-firmware-qca988x sfdisk partx-utils resize2fs; do
  grep -q "^$p " "$MAN" || { echo "manifest missing: $p"; exit 1; }
done
for p in luci-i18n-base-zh-cn; do
  grep -q "^$p " "$MAN" || { echo "manifest missing translation: $p (CONFIG_LUCI_LANG_zh_Hans not applied?)"; exit 1; }
done
tar -tzf "$TAR" | sed 's|^\./||' > /tmp/rootfs-files.txt
for f in usr/sbin/edge610-install \
         etc/init.d/edge610 etc/modprobe.d/edge610.conf \
         etc/uci-defaults/zzz99-edge610-network etc/uci-defaults/zzz98-edge610-resize \
         etc/uci-defaults/zzz99-edge610-network-modem \
         etc/uci-defaults/zzz99-edge610-mwan3 \
         etc/openclash/core/clash_meta; do
  grep -qx "$f" /tmp/rootfs-files.txt || { echo "rootfs missing: $f"; exit 1; }
done
# Listing into a file on purpose: `tar | grep -q` dies of SIGPIPE once grep
# matches, and pipefail turns that into a false failure.
tar -tvzf "$TAR" > /tmp/rootfs-modes.txt
grep -q '^-rwxr-xr-x .*usr/sbin/edge610-install$' /tmp/rootfs-modes.txt \
  || { echo "edge610-install is missing or not executable"; exit 1; }
for b in sfdisk partx resize2fs; do
  grep -qE "/$b$" /tmp/rootfs-files.txt || { echo "binary missing: $b"; exit 1; }
done
grep -qE '^lib/firmware/ath10k/QCA988X/hw2.0/firmware-[0-9]+\.bin$' /tmp/rootfs-files.txt \
  || { echo "ath10k QCA988X firmware missing"; exit 1; }
NW=package/edge610-board/files/etc/uci-defaults/zzz99-edge610-network
grep -q "uci -q set network.wan='interface'" "$NW" || { echo "WAN interface missing from network defaults"; exit 1; }
grep -q "uci -q set network.wan.device='lan6'" "$NW" || { echo "WAN is not on lan6"; exit 1; }
grep -q 'for port in lan1 lan2 lan3 lan4 lan5 eth3 eth2; do' "$NW" || { echo "LAN bridge is not the DSA ports plus both SFP cages"; exit 1; }
! grep -qE 'for port in .*lan6' "$NW" || { echo "lan6 must not be in the LAN bridge"; exit 1; }
for m in edge610_switch_standalone edge610_dsa i2c-ismt mv88e6xxx ixgbe; do
  find build_dir -path '*/lib/modules/*' -name "$m.ko" | grep -q . || { echo "module missing: $m"; exit 1; }
done
find build_dir -path '*/lib/modules/*' -name 'dsa*.ko' | grep -q . || { echo "dsa core missing"; exit 1; }
# uci section names may be quoted but must not contain '-' (br-lan is anonymous)
! grep -qE "^config [a-z]+ '[^']*-[^']*'" package/edge610-board/files/etc/uci-defaults/zzz99-edge610-network || { echo "uci section name contains '-': package/edge610-board/files/etc/uci-defaults/zzz99-edge610-network"; exit 1; }
KO="$(find build_dir -path '*/lib/modules/*' -name edge610_dsa.ko | head -n1)"
strings "$KO" | grep -q lan6 || { echo "port rename missing"; exit 1; }

echo
echo "=== BUILD OK $(date -u) ==="
ls -la "$IMG"

# Give this image its own rootfs PARTUUID. OpenWrt derives every GUID from
# md5(SOURCE_DATE_EPOCH + LINUX_VERMAGIC), so without this step a stick written
# from any release mounts the eMMC rootfs (same root=PARTUUID) instead of its
# own, and edge610-install never runs.
log "re-UUID the image"
TMPUUID="$(mktemp -d)"
gzip -dc "$IMG" > "$TMPUUID/img"
python3 "$REPO/scripts/image-uuid.py" "$TMPUUID/img"
gzip -9 -n -c "$TMPUUID/img" > "$IMG"
rm -rf "$TMPUUID"
( cd "$(dirname "$IMG")" && sed -i "s|^[0-9a-f]*  $(basename "$IMG")\$|$(sha256sum "$(basename "$IMG")")|" sha256sums )

# Timestamped copy for archiving (the build output keeps its canonical name
# so sha256sums and scripted paths stay valid). GMT+8, machine TZ independent.
STAMP="$(TZ=Asia/Shanghai date +%Y%m%d-%H%M)"
ART="${ARTIFACTS_DIR:-$WORK/artifacts}"
mkdir -p "$ART"
cp "$IMG" "$ART/edge610-$STAMP.img.gz"
cp "$MAN" "$ART/edge610-$STAMP.manifest"
ln -sfn "$ART/edge610-$STAMP.img.gz" "$ART/edge610-latest.img.gz"
# Board packages (kmods + files) for ImageBuilder / on-device apk upgrades.
mkdir -p "$ART/repo"
# Clear the previous run so an old revision cannot be published alongside the
# new one. i2c-ismt is part of this package's build but not named edge610*.
rm -f "$ART/repo"/*.apk
find bin \( -name 'edge610*.apk' -o -name 'kmod-edge610-*.apk' -o -name 'kmod-i2c-ismt-*.apk' \) \
  -exec cp -f {} "$ART/repo/" \;
ls -l "$ART/repo"
echo "artifact: $ART/edge610-$STAMP.img.gz"
echo "$IMG"
