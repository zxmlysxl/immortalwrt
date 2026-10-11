#!/usr/bin/env python3
"""Fix luci-app-znetcontrol Makefile: replace wrong $(CP) with correct ./luasrc copy."""
import sys

MAKEFILE = "feeds/zuoxm/luci-app-znetcontrol/Makefile"

with open(MAKEFILE, "r") as f:
    mk = f.read()

# The Makefile has a wrong Build/Prepare: $(CP) $(PKG_BUILD_DIR)/* ... copies nothing useful.
# Build/Prepare runs BEFORE unpack, so $(PKG_BUILD_DIR) doesn't exist yet.
# The luasrc/ dir is inside the extracted source; we need: $(CP) ./luasrc $(PKG_BUILD_DIR)/luasrc
wrong_line = "\t$(CP) $(PKG_BUILD_DIR)/* $(PKG_BUILD_DIR)/ 2>/dev/null || :"
right_line = "\t$(CP) ./luasrc $(PKG_BUILD_DIR)/luasrc"

if wrong_line in mk:
    mk = mk.replace(wrong_line, right_line)
    with open(MAKEFILE, "w") as f:
        f.write(mk)
    print("Fixed: replaced wrong $(CP) with correct $(CP) ./luasrc")
else:
    # Also check if it's already fixed or uses different quoting
    if right_line in mk:
        print("Already fixed: correct $(CP) ./luasrc is present")
    else:
        print("Warning: neither wrong nor correct line found, printing Build/Prepare block")
        import re
        m = re.search(r"define Build/Prepare\n.*?\nendef", mk, re.DOTALL)
        if m:
            print(repr(m.group()))
        sys.exit(0)
