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
if [ ! -s "$CORE" ]; then
  log "download mihomo amd64-v1"
  mkdir -p "$(dirname "$CORE")"
  CORE_URL="$(curl -fsSL https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
    | jq -r '.assets[] | select(.name | contains("linux-amd64-v1") and (endswith(".gz"))) | .browser_download_url' \
    | head -n1 || true)"
  [ -n "$CORE_URL" ] || CORE_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/mihomo-linux-amd64-v1-go120-v1.19.33.gz"
  echo "core: $CORE_URL"
  echo "$CORE_URL" | grep -q "linux-amd64-v1"
  curl -fL -o /tmp/mihomo.gz "$CORE_URL"
  gzip -dc /tmp/mihomo.gz > "$CORE"
  chmod 755 "$CORE"
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
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y
CONFIG_PACKAGE_luci-i18n-package-manager-zh-cn=y
CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y
CONFIG_PACKAGE_luci-i18n-statistics-zh-cn=y
CONFIG_PACKAGE_luci-i18n-ddns-zh-cn=y
CONFIG_PACKAGE_luci-i18n-sqm-zh-cn=y
CONFIG_PACKAGE_ethtool=y
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
CONFIG_PACKAGE_block-mount=y
CONFIG_PACKAGE_kmod-usb-net-rtl8152=y
CONFIG_PACKAGE_kmod-usb-net-asix-ax88179=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ether=y
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_luci-app-mwan3=y
CONFIG_PACKAGE_luci-app-pbr=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-app-nlbwmon=y
CONFIG_PACKAGE_luci-app-wol=y
CONFIG_PACKAGE_luci-app-udpxy=y
CONFIG_PACKAGE_luci-app-omcproxy=y
CONFIG_PACKAGE_luci-app-watchcat=y
CONFIG_PACKAGE_luci-app-lldpd=y
CONFIG_PACKAGE_luci-app-adblock-fast=y
CONFIG_PACKAGE_luci-app-adguardhome=y
CONFIG_PACKAGE_adguardhome=y
CONFIG_PACKAGE_luci-app-smartdns=y
CONFIG_PACKAGE_smartdns=y
CONFIG_PACKAGE_luci-app-https-dns-proxy=y
CONFIG_PACKAGE_luci-app-ksmbd=y
CONFIG_PACKAGE_ksmbd-server=y
CONFIG_PACKAGE_luci-app-hd-idle=y
CONFIG_PACKAGE_luci-app-openlist=y
CONFIG_PACKAGE_luci-app-filebrowser=y
CONFIG_PACKAGE_luci-app-aria2=y
CONFIG_PACKAGE_luci-app-transmission=y
CONFIG_PACKAGE_luci-app-commands=y
CONFIG_PACKAGE_luci-app-irqbalance=y
CONFIG_PACKAGE_luci-app-p910nd=y
CONFIG_PACKAGE_luci-app-ser2net=y
CONFIG_PACKAGE_luci-app-filemanager=y
CONFIG_PACKAGE_luci-app-openvpn=y
CONFIG_PACKAGE_luci-app-tailscale-community=y
CONFIG_PACKAGE_tailscale=y
CONFIG_PACKAGE_luci-app-frpc=y
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_PACKAGE_dockerd=y
CONFIG_PACKAGE_containerd=y
CONFIG_PACKAGE_runc=y
CONFIG_PACKAGE_tini=y
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-store=y
CONFIG_PACKAGE_luci-lib-taskd=y
CONFIG_PACKAGE_taskd=y
CONFIG_PACKAGE_xz-utils=y
CONFIG_PACKAGE_luci-compat=y
EOF
if [ -f .config ]; then
  added=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    grep -qxF "$line" .config || { printf '%s\n' "$line" >> .config; added=$((added + 1)); }
  done < /tmp/edge610-seed.config
  [ "$added" = 0 ] || log "merged $added new symbol(s) into .config"
else
  log "write .config seed"
  cp /tmp/edge610-seed.config .config
fi
log "make defconfig"
make defconfig

for sym in \
  CONFIG_TARGET_x86_64=y \
  CONFIG_TARGET_ROOTFS_PARTSIZE=1024 \
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
  CONFIG_PACKAGE_ethtool=y \
  CONFIG_PACKAGE_iperf3=y \
  CONFIG_PACKAGE_kmod-hwmon-coretemp=y \
  CONFIG_PACKAGE_kmod-ath10k=y \
  CONFIG_PACKAGE_ath10k-firmware-qca988x=y \
  CONFIG_PACKAGE_sfdisk=y \
  CONFIG_PACKAGE_partx-utils=y \
  CONFIG_PACKAGE_resize2fs=y \
  CONFIG_PACKAGE_luci-theme-argon=y \
  CONFIG_PACKAGE_luci-app-store=y \
  CONFIG_PACKAGE_luci-app-dockerman=y \
  CONFIG_PACKAGE_luci-app-adguardhome=y \
  CONFIG_PACKAGE_luci-app-ksmbd=y; do
  grep -q "^${sym}$" .config || { echo "MISSING after defconfig: $sym"; exit 1; }
done
grep -q '^# CONFIG_PACKAGE_dnsmasq is not set' .config || { echo "plain dnsmasq still enabled"; exit 1; }

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

log "make -j$(nproc)"
make -j"$(nproc)"

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
tar -tzf "$TAR" | sed 's|^\./||' > /tmp/rootfs-files.txt
for f in etc/init.d/edge610 etc/modprobe.d/edge610.conf \
         etc/uci-defaults/zzz99-edge610-network etc/uci-defaults/zzz98-edge610-resize \
         etc/openclash/core/clash_meta; do
  grep -qx "$f" /tmp/rootfs-files.txt || { echo "rootfs missing: $f"; exit 1; }
done
for b in sfdisk partx resize2fs; do
  grep -qE "/$b$" /tmp/rootfs-files.txt || { echo "binary missing: $b"; exit 1; }
done
grep -qE '^lib/firmware/ath10k/QCA988X/hw2.0/firmware-[0-9]+\.bin$' /tmp/rootfs-files.txt \
  || { echo "ath10k QCA988X firmware missing"; exit 1; }
grep -q "option device 'eth2'" package/edge610-board/files/etc/uci-defaults/zzz99-edge610-network \
  || { echo "SFP WAN (eth2) missing from network defaults"; exit 1; }
for m in edge610_switch_standalone edge610_dsa i2c-ismt mv88e6xxx ixgbe; do
  find build_dir -path '*/lib/modules/*' -name "$m.ko" | grep -q . || { echo "module missing: $m"; exit 1; }
done
find build_dir -path '*/lib/modules/*' -name 'dsa*.ko' | grep -q . || { echo "dsa core missing"; exit 1; }
# uci section names cannot contain '-': br-lan must be an anonymous section
! grep -qE "^config [a-z]+ '" package/edge610-board/files/etc/uci-defaults/zzz99-edge610-network || { echo "uci section names must be anonymous (no quotes)"; exit 1; }
KO="$(find build_dir -path '*/lib/modules/*' -name edge610_dsa.ko | head -n1)"
strings "$KO" | grep -q lan6 || { echo "port rename missing"; exit 1; }

echo
echo "=== BUILD OK $(date -u) ==="
ls -la "$IMG"
echo "$IMG"
