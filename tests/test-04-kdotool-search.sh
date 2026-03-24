#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test: kdotool search reliability
#
# Polls "kdotool search" continuously for 30 seconds, checking that every
# window present in the initial baseline remains visible on every poll.
# Captures full raw output on any failure so the exact response is visible.
#
# Must run before any test that queries windows (test-05+).

_run_test_04() {

print_section_header "kdotool search Reliability (30s)"

local duration=30
local poll_interval=0.1   # 100ms between polls

# ============================================================================
# Baseline snapshot
# ============================================================================

test_start "kdotool search baseline"

local baseline_output
baseline_output=$(kdotool search 2>&1)
local baseline_exit=$?

if [[ $baseline_exit -ne 0 ]]; then
    test_fail "kdotool search failed (exit $baseline_exit): $baseline_output"
    gate_failed
    return
fi

local -a baseline_uuids=()
local uuid
while IFS= read -r uuid; do
    [[ -n "$uuid" ]] && baseline_uuids+=("$uuid")
done <<< "$baseline_output"

local baseline_count=${#baseline_uuids[@]}
if [[ $baseline_count -eq 0 ]]; then
    test_fail "kdotool search returned 0 windows — nothing to test"
    gate_failed
    return
fi
test_pass
echo "    Baseline: $baseline_count window(s)"

# ============================================================================
# Continuous polling
# ============================================================================

test_start "kdotool search consistency (${duration}s @ ${poll_interval}s)"

local start_time end_time now elapsed
local total_polls=0
local failures=0
local exit_failures=0
local empty_results=0
local missing_uuid_polls=0
local -a failure_log=()
# Cap logged failures so the output stays readable
local max_logged=50

start_time=$(date +%s%3N)
end_time=$(( start_time + duration * 1000 ))

while (( $(date +%s%3N) < end_time )); do
    ((total_polls++))
    now=$(date +%s%3N)
    elapsed=$(( now - start_time ))

    local output
    output=$(kdotool search 2>&1)
    local exit_code=$?

    # --- Check 1: exit code ---
    if [[ $exit_code -ne 0 ]]; then
        ((failures++))
        ((exit_failures++))
        if (( ${#failure_log[@]} < max_logged )); then
            failure_log+=("  +${elapsed}ms  EXIT_FAIL  code=$exit_code  output='$output'")
        fi
        sleep "$poll_interval"
        continue
    fi

    # --- Check 2: non-empty output ---
    if [[ -z "$output" ]]; then
        ((failures++))
        ((empty_results++))
        if (( ${#failure_log[@]} < max_logged )); then
            failure_log+=("  +${elapsed}ms  EMPTY      exit=0  output=''")
        fi
        sleep "$poll_interval"
        continue
    fi

    # --- Check 3: all baseline UUIDs still present ---
    # Build a lookup set from current output for O(n) comparison
    local -A current_set=()
    local current_count=0
    local line
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            current_set["$line"]=1
            ((current_count++))
        fi
    done <<< "$output"

    local missing_list=""
    local missing_count=0
    for uuid in "${baseline_uuids[@]}"; do
        if [[ ! -v current_set[$uuid] ]]; then
            missing_list+=" $uuid"
            ((missing_count++))
        fi
    done
    unset current_set

    if [[ $missing_count -gt 0 ]]; then
        ((failures++))
        ((missing_uuid_polls++))
        if (( ${#failure_log[@]} < max_logged )); then
            failure_log+=("  +${elapsed}ms  MISSING    ${current_count}/${baseline_count} returned, $missing_count missing:$missing_list")
            failure_log+=("               raw output:")
            while IFS= read -r line; do
                failure_log+=("                 $line")
            done <<< "$output"
        fi
    fi

    sleep "$poll_interval"
done

# ============================================================================
# Results
# ============================================================================

if [[ $failures -eq 0 ]]; then
    test_pass
    echo "    $total_polls polls, 0 failures"
else
    test_fail "$failures/$total_polls polls had inconsistent results"
    echo "    Exit failures:       $exit_failures"
    echo "    Empty results:       $empty_results"
    echo "    Missing UUID polls:  $missing_uuid_polls"
    echo ""
    echo "    Failure details (first $max_logged):"
    local detail
    for detail in "${failure_log[@]}"; do
        echo "$detail"
    done
    if (( failures > max_logged )); then
        echo "    ... and $(( failures - max_logged )) more"
    fi
    gate_failed
fi

}
_run_test_04
