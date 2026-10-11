#!/usr/bin/env python3
"""Fix luci-app-znetcontrol Makefile: replace wrong $(CP) with correct ./luasrc copy."""
import re
import sys

MAKEFILE = "feeds/zuoxm/luci-app-znetcontrol/Makefile"

with open(MAKEFILE, "r") as f:
    mk = f.read()

# The Makefile's Build/Prepare step has a wrong copy:
#   $(CP) $(PKG_BUILD_DIR)/* $(PKG_BUILD_DIR)/ 2>/dev/null || :
# This copies nothing because Build/Prepare runs BEFORE unpack,
# so $(PKG_BUILD_DIR) doesn't exist yet.
# luasrc/ is inside the extracted source tarball, not the build dir.
# Correct: copy from ./luasrc into $(PKG_BUILD_DIR)/luasrc
wrong_line = "\t$(CP) $(PKG_BUILD_DIR)/* $(PKG_BUILD_DIR)/ 2>/dev/null || :"
right_line = "\t$(CP) ./luasrc $(PKG_BUILD_DIR)/luasrc"

if wrong_line in mk:
    mk = mk.replace(wrong_line, right_line)
    with open(MAKEFILE, "w") as f:
        f.write(mk)
    print("Fixed: replaced wrong $(CP) with correct $(CP) ./luasrc")
    sys.exit(0)

# Check if already fixed
if right_line in mk:
    print("Already fixed: correct $(CP) ./luasrc is present")
    sys.exit(0)

# Neither found - print the Build/Prepare block for debugging
print("Warning: neither wrong nor correct line found, Build/Prepare block:")
m = re.search(r"define Build/Prepare\n.*?\nendef", mk, re.DOTALL)
if m:
    print(repr(m.group()))
sys.exit(0)
