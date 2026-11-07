#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Unit tests: the snapshot client picks qdbus-qt6 or qdbus6, whichever is
# installed, and QDBUS_BIN overrides both. PATH holds only stub binaries;
# nothing here calls the session bus.

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
# shellcheck source=../../lib/kwin-scripts/qdbus.sh
source "$LIB_DIR/kwin-scripts/qdbus.sh"

unset QDBUS_BIN

# make_stub_dir <dir> <name...>: a PATH dir holding stub binaries
make_stub_dir() {
    local dir="$1"
    shift
    mkdir -p "$dir"
    local name=""
    for name in "$@"; do
        printf '#!/bin/sh\nexit 0\n' > "$dir/$name"
        chmod +x "$dir/$name"
    done
}

only_qdbus6="$UNIT_TMP/bin-qdbus6"
only_qt6="$UNIT_TMP/bin-qdbus-qt6"
both="$UNIT_TMP/bin-both"
neither="$UNIT_TMP/bin-neither"
make_stub_dir "$only_qdbus6" qdbus6
make_stub_dir "$only_qt6" qdbus-qt6
make_stub_dir "$both" qdbus-qt6 qdbus6
make_stub_dir "$neither"

assert_eq "qdbus: picks qdbus6 when it is the only one" \
    "qdbus6" "$(PATH="$only_qdbus6" select_qdbus_bin)"
assert_eq "qdbus: picks qdbus-qt6 when it is the only one" \
    "qdbus-qt6" "$(PATH="$only_qt6" select_qdbus_bin)"
assert_eq "qdbus: prefers qdbus-qt6 when both exist" \
    "qdbus-qt6" "$(PATH="$both" select_qdbus_bin)"
assert_eq "qdbus: QDBUS_BIN wins over both" \
    "/opt/qt/bin/qdbus" "$(QDBUS_BIN=/opt/qt/bin/qdbus PATH="$both" select_qdbus_bin)"
assert_eq "qdbus: QDBUS_BIN wins when neither is installed" \
    "my-qdbus" "$(QDBUS_BIN=my-qdbus PATH="$neither" select_qdbus_bin)"
assert_eq "qdbus: empty QDBUS_BIN is ignored" \
    "qdbus6" "$(QDBUS_BIN="" PATH="$only_qdbus6" select_qdbus_bin)"

finish
