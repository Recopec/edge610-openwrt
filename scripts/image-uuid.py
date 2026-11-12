#!/usr/bin/env python3
"""Give an Edge 610 image its own rootfs PARTUUID.

OpenWrt derives every image GUID from md5(SOURCE_DATE_EPOCH + LINUX_VERMAGIC),
so all builds of a given tree share the same partition UUIDs. GRUB boots with
root=PARTUUID=, which means a stick written from a new release mounts the eMMC
rootfs of an older install (the UUIDs match) instead of its own - the stick
never boots its own system and edge610-install is not there.

Rewriting the image's p2 PARTUUID (and the matching root= in its grub.cfg)
makes every image distinct, so a stick and an eMMC only ever collide when they
carry the very same image.

Usage: image-uuid.py <image.img>        (uncompressed raw image, edited in place)

Works on a plain file: no loop device, no root. The grub.cfg rewrite is a
fixed-length byte substitution inside p1, so the FAT filesystem is untouched.
"""

import os
import re
import subprocess
import sys
import uuid

SECTOR = 512


def part_index(name):
    """'/dev/sdb2' -> '2', '/tmp/t.img2' -> '2', '/dev/mmcblk0p2' -> '2'."""
    found = re.search(r"(\d+)$", name)
    return found.group(1) if found else ""


def read_gpt(path):
    """Return {partition index: UUID} as upper-case strings."""
    out = subprocess.run(["sfdisk", "-d", path], capture_output=True, text=True, check=True).stdout
    uuids = {}
    for line in out.splitlines():
        fields = line.split()
        if not fields or not fields[0].startswith("/"):
            continue
        idx = part_index(fields[0])
        for token in fields:
            if token.startswith("uuid="):
                uuids[idx] = token[5:].rstrip(",").upper()
    return uuids


def partition_extent(path, index):
    """(start_byte, length_byte) of partition <index> from sfdisk -d."""
    out = subprocess.run(["sfdisk", "-d", path], capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        fields = line.split()
        if not fields or not fields[0].startswith("/") or part_index(fields[0]) != str(index):
            continue
        start = size = None
        for i, token in enumerate(fields):
            if token == "start=":
                start = int(fields[i + 1].rstrip(","))
            if token == "size=":
                size = int(fields[i + 1].rstrip(","))
        if start is not None and size is not None:
            return start * SECTOR, size * SECTOR
    raise SystemExit(f"partition {index} not found in {path}")


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__.strip().splitlines()[-1])
    path = sys.argv[1]
    before = read_gpt(path)
    if "2" not in before:
        raise SystemExit(f"{path} has no p2 - not an Edge 610 image")

    old = before["2"]
    new = str(uuid.uuid4()).upper()
    if old == new:
        raise SystemExit("refusing to keep the same UUID")

    subprocess.run(["sfdisk", "--part-uuid", path, "2", new], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Rewrite root=PARTUUID=<old> inside p1 (grub.cfg). Same length, so the
    # FAT file does not move and no metadata has to be updated.
    start, length = partition_extent(path, 1)
    with open(path, "r+b") as f:
        f.seek(start)
        blob = f.read(length)
        hits = blob.count(old.lower().encode()) + blob.count(old.encode())
        if hits == 0:
            raise SystemExit("root= UUID not found in p1 - image layout changed?")
        blob = blob.replace(old.lower().encode(), new.lower().encode())
        blob = blob.replace(old.encode(), new.encode())
        f.seek(start)
        f.write(blob)
        f.flush()
        os.fsync(f.fileno())

    after = read_gpt(path)["2"]
    if after != new:
        raise SystemExit(f"uuid write did not stick ({after})")
    print(f"rootfs PARTUUID {old} -> {new} ({hits} grub.cfg reference(s))")


if __name__ == "__main__":
    main()
