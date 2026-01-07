#!/bin/bash

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






