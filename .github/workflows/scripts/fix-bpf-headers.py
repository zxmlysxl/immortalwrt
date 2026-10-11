#!/usr/bin/env python3
"""Patch bpf-headers Makefile to skip backport patches that target newer kernels."""
import re
import sys

MAKEFILE = "package/kernel/bpf-headers/Makefile"
if len(sys.argv) > 1:
    MAKEFILE = sys.argv[1]

if not __import__("os").path.isfile(MAKEFILE):
    print(f"⚠️ {MAKEFILE} not found, skipping")
    sys.exit(0)

with open(MAKEFILE, "r") as f:
    mk = f.read()

old = "define Build/Patch\n\t$(Kernel/Patch/Default)\nendef"
new = "define Build/Patch\n\t# No patches applied: bpf-headers uses base 6.12.x headers only\nendef"

if old in mk:
    mk = mk.replace(old, new)
    with open(MAKEFILE, "w") as f:
        f.write(mk)
    print("✅ bpf-headers Build/Patch overridden to no-op")
else:
    mk2 = re.sub(
        r'(define Build/Patch\n)\s*\$\(Kernel/Patch/Default\)(\nendef)',
        r'\1\t# No patches applied: bpf-headers uses base 6.12.x headers only\2',
        mk
    )
    if mk2 != mk:
        with open(MAKEFILE, "w") as f:
            f.write(mk2)
        print("✅ bpf-headers Build/Patch overridden (alt method)")
    else:
        print("⚠️ bpf-headers Build/Patch already modified or format differs")
