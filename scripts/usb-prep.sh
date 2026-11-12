#!/bin/sh
# usb-prep.sh - make a USB stick written from an Edge 610 image bootable on its
# own when the same image also lives on another disk (typically the eMMC).
#
# Why: the image's GPT partition UUIDs are derived from md5(SOURCE_DATE_EPOCH +
# LINUX_VERMAGIC), i.e. they are identical in every build of a given tree. Write
# that image to the eMMC and to a stick and both disks carry the same PARTUUID;
# grub boots with root=PARTUUID=<that value>, so the kernel mounts whichever disk
# it enumerates first - the stick's own rootfs is never used.
#
# This re-UUIDs the stick's root partition (p2) and rewrites the matching
# root= in p1's grub.cfg. The stick's data partitions are otherwise untouched.
#
# Usage:  sudo ./usb-prep.sh /dev/sdX          (whole disk, not a partition)
#
# Run it from a system that is NOT booted from that stick.

set -eu

dev=${1:?usage: usb-prep.sh /dev/sdX}
[ -b "$dev" ] || { echo "$dev is not a block device"; exit 1; }

# Refuse to touch a disk that hosts the running root or /boot.
for mnt in / /boot; do
	cur=$(awk -v m="$mnt" '$2 == m {print $1}' /proc/mounts)
	if [ -n "$cur" ] && [ "$(readlink -f "$cur")" = "$(readlink -f "$dev")" ]; then
		echo "$dev holds the running $mnt - run this from another system"; exit 1
	fi
done

command -v sfdisk >/dev/null || { echo "sfdisk not found"; exit 1; }

# Sanity: our layout is p1 = kernel (vfat), p2 = rootfs (ext4, 1 GiB in the image).
sfdisk -d "$dev" | grep -q "^$dev"2 || { echo "$dev2 missing - not an Edge 610 image?"; exit 1; }

new=$(cat /proc/sys/kernel/random/uuid | tr 'a-f' 'A-F')
old=$(sfdisk -d "$dev" | grep "^$dev"2 | sed -n 's/.*uuid=\([0-9A-Fa-f-]*\).*/\1/p')
[ -n "$old" ] || { echo "cannot read the rootfs partition UUID from $dev"; exit 1; }
echo "rootfs partition UUID: $old -> $new"

sfdisk --part-uuid "$dev" 2 "$new" >/dev/null 2>&1 || { echo "sfdisk --part-uuid failed"; exit 1; }
sync

mnt=$(mktemp -d)
trap 'umount "$mnt" 2>/dev/null; rmdir "$mnt" 2>/dev/null' EXIT
mount "${dev}1" "$mnt" || { echo "cannot mount ${dev}1"; exit 1; }
cfg="$mnt/boot/grub/grub.cfg"
[ -f "$cfg" ] || cfg="$mnt/grub/grub.cfg"
[ -f "$cfg" ] || { echo "grub.cfg not found on ${dev}1"; exit 1; }

low=$(echo "$new" | tr 'A-F' 'a-f')
sed -i "s/$old/$(echo "$low" | tr 'a-f' 'A-F')/Ig" "$cfg"
grep -q "$low" "$cfg" || { echo "grub.cfg was not updated"; exit 1; }
sync

echo "done: ${dev}2 now boots on its own; keep the eMMC side untouched."
grep -n 'root=' "$cfg" | head -2
