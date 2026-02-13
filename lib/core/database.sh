#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

# shellcheck source=../db/window-tracking.sh
source "${LIB_DIR}/db/window-tracking.sh"

normalize_boolean () {
    boolean="$1"

    if [[ "$boolean" == "TRUE" || "$boolean" == "true" || "$boolean" == "1" ]]; then
        boolean="TRUE"
    elif [[ "$boolean" == "FALSE" || "$boolean" == "false" || "$boolean" == "0" ]]; then
        boolean="FALSE"
    fi

    echo "$boolean"
}






