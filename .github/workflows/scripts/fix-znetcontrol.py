#!/usr/bin/env python3
"""Fix luci-app-znetcontrol Makefile: tab indent + Build/Prepare copy step."""
import re
import sys

MAKEFILE = "feeds/zuoxm/luci-app-znetcontrol/Makefile"

with open(MAKEFILE, "r") as f:
    mk = f.read()

# Fix 1: Lines 37-39 use 2 spaces for recipe indent (gmake 4.4+ requires tab)
# Match any 2 leading spaces at start of recipe lines inside Build/Prepare
fixed = re.sub(r"(define Build/Prepare\n)(    )", r"\1\t", mk)
if fixed != mk:
    print("Fixed tab indentation in Build/Prepare")
    mk = fixed
else:
    print("Tab indentation already correct or pattern not found")

# Fix 2: Build/Prepare runs BEFORE unpack, so $(PKG_BUILD_DIR)/luasrc doesn't exist.
# Insert $(CP) ./luasrc $(PKG_BUILD_DIR)/luasrc before $(SED) line.
# Note: upstream uses | as sed delimiter, not /
old_block = (
    "define Build/Prepare\n"
    "\t$(SED) 's|{{PKG_VERSION}}|$(PKG_VERSION)|g' "
    "$(PKG_BUILD_DIR)/luasrc/controller/znetcontrol.lua\n"
    "endef"
)
new_block = (
    "define Build/Prepare\n"
    "\t$(CP) ./luasrc $(PKG_BUILD_DIR)/luasrc\n"
    "\t$(SED) 's|{{PKG_VERSION}}|$(PKG_VERSION)|g' "
    "$(PKG_BUILD_DIR)/luasrc/controller/znetcontrol.lua\n"
    "endef"
)

if old_block in mk:
    mk = mk.replace(old_block, new_block)
    with open(MAKEFILE, "w") as f:
        f.write(mk)
    print("Fixed Build/Prepare: added $(CP) before $(SED)")
else:
    print("Build/Prepare block not found (may already be fixed or format differs)")
    sys.exit(0)
