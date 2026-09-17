#!/usr/bin/env python3
"""Patch firmware image: replace %D/%V/%C Make variables in openwrt_release and banner."""

import gzip
import os
import shutil
import subprocess
import sys
import tempfile


def main():
    img_path = os.environ.get("FIRM_GZ", "")
    build_date = os.environ.get("BUILD_DATE_SHORT", "20260916")
    build_code = os.environ.get("BUILD_CODE", "26.09.16")

    if not img_path or not os.path.exists(img_path):
        print(f"   SKIP: firmware not found at {img_path}")
        sys.exit(0)

    print(f"   Patching: {img_path}")

    with tempfile.TemporaryDirectory() as tmpdir:
        cpio_path = os.path.join(tmpdir, "rootfs.cpio")
        try:
            # Decompress
            with gzip.open(img_path, "rb") as f:
                with open(cpio_path, "wb") as out:
                    out.write(f.read())

            # Extract CPIO — tolerate extraction errors (e.g. missing files)
            rootfs = os.path.join(tmpdir, "rootfs")
            os.makedirs(rootfs)
            result = subprocess.run(
                ["cpio", "-id", "-D", rootfs],
                stdin=open(cpio_path, "rb"),
                capture_output=True,
            )
            if result.returncode != 0:
                print(f"   WARN: cpio extraction returned {result.returncode}: {result.stderr[:200]}")
        except Exception as e:
            print(f"   WARN: failed to extract firmware: {e}")
            sys.exit(0)

        patched = False

        # Patch etc/openwrt_release
        or_path = os.path.join(rootfs, "etc", "openwrt_release")
        if os.path.exists(or_path):
            try:
                with open(or_path) as f:
                    content = f.read()
                content = (
                    content.replace("%D", "Z-ImmortalWrt")
                    .replace("%V", build_date)
                    .replace("%C", build_code)
                )
                with open(or_path, "w") as f:
                    f.write(content)
                print(f"   Patched openwrt_release")
                patched = True
            except Exception as e:
                print(f"   WARN: failed to patch openwrt_release: {e}")

        # Patch etc/banner
        banner_path = os.path.join(rootfs, "etc", "banner")
        if os.path.exists(banner_path):
            try:
                with open(banner_path) as f:
                    content = f.read()
                content = (
                    content.replace("%D", "Z-ImmortalWrt")
                    .replace("%V", build_date)
                    .replace("%C", build_code)
                )
                with open(banner_path, "w") as f:
                    f.write(content)
                print(f"   Patched banner")
                patched = True
            except Exception as e:
                print(f"   WARN: failed to patch banner: {e}")

        if not patched:
            print(f"   SKIP: no files to patch")
            sys.exit(0)

        try:
            # Repack CPIO
            new_cpio = os.path.join(tmpdir, "new_rootfs.cpio")
            with open(new_cpio, "wb") as f:
                subprocess.run(
                    ["cpio", "-oc"],
                    stdin=subprocess.DEVNULL,
                    stdout=f,
                    check=True,
                    cwd=rootfs,
                )

            # Recompress
            new_img = os.path.join(tmpdir, "new_firmware.img.gz")
            with open(new_cpio, "rb") as f_in:
                with gzip.open(new_img, "wb", compresslevel=6) as f_out:
                    f_out.writelines(f_in)

            shutil.copy(new_img, img_path)
            print(f"   Firmware patched and saved: {img_path}")
        except Exception as e:
            print(f"   WARN: failed to repack firmware: {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
