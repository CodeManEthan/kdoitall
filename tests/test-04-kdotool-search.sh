#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test 04: kdotool search reliability
#
# Polls "kdotool search" continuously for 30 seconds via the same retry
# policy used by the production wrapper _kdotool_search_safe in
# lib/window-management/window.sh: up to 2 retries (50ms each) on empty.
# Verifies that the wrapper-equivalent behavior never produces a sustained
# empty result when the system has windows.
#
# Background: kdotool's KWin script emits each window UUID as a separate
# asynchronous DBus signal, then returns. Messages emitted near the end of
# iteration may still be in flight when kdotool reads its message buffer.
# This produces two observable failure modes:
#   - Empty stdout (all messages in flight) — addressed by the wrapper here.
#   - Partial stdout (tail messages in flight) — NOT addressed at this layer;
#     the production code handles partials via caller-side validation at
#     destructive call sites and via POE retry loop resilience.
#
# Test policy:
#   - Hard fail: exit code != 0 from kdotool, or sustained empty after retry.
#   - Soft signal: partial responses are reported as telemetry (rate, count)
#     but do NOT fail the test, because the wrapper at this layer doesn't
#     promise to mask them.
#
# Must run before any test that queries windows (test-05+).

_run_test_04() {

print_section_header "Test 04: kdotool search Reliability (30s)"

local duration=30
local poll_interval=0.1   # 100ms between polls

# ============================================================================
# Baseline snapshot (uses wrapper-equivalent retry to avoid a flaky baseline)
# ============================================================================

test_start "kdotool search baseline"

local baseline_output
baseline_output=$(kdotool search 2>/dev/null)
if [[ -z "$baseline_output" ]]; then
    sleep 0.05
    baseline_output=$(kdotool search 2>/dev/null)
fi

local -a baseline_uuids=()
local uuid
while IFS= read -r uuid; do
    [[ -n "$uuid" ]] && baseline_uuids+=("$uuid")
done <<< "$baseline_output"

local baseline_count=${#baseline_uuids[@]}
if [[ $baseline_count -eq 0 ]]; then
    test_fail "kdotool search returned 0 windows on baseline (after retry) — nothing to test"
    gate_failed
    return
fi
test_pass
echo "    Baseline: $baseline_count window(s)"

# ============================================================================
# Continuous polling — mirrors _kdotool_search_safe (single retry on empty)
# ============================================================================

test_start "kdotool search consistency (${duration}s @ ${poll_interval}s)"

local start_time end_time now elapsed
local total_polls=0
local hard_failures=0
local exit_failures=0
local empty_after_retry=0
local transient_empties=0
local partial_responses=0
local -a failure_log=()
local max_logged=20

start_time=$(date +%s%3N)
end_time=$(( start_time + duration * 1000 ))

while (( $(date +%s%3N) < end_time )); do
    ((total_polls++))
    now=$(date +%s%3N)
    elapsed=$(( now - start_time ))

    local output exit_code
    output=$(kdotool search 2>/dev/null)
    exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        ((hard_failures++))
        ((exit_failures++))
        if (( ${#failure_log[@]} < max_logged )); then
            failure_log+=("  +${elapsed}ms  EXIT_FAIL  code=$exit_code")
        fi
        sleep "$poll_interval"
        continue
    fi

    # Up to 2 retries on empty (mirrors _kdotool_search_safe). Counts a
    # transient empty if the FIRST call was empty (regardless of which
    # retry recovers it). Counts as a hard "sustained empty" failure only
    # if all 3 calls (initial + 2 retries) return empty.
    if [[ -z "$output" ]]; then
        ((transient_empties++))
        local retry_idx
        for retry_idx in 1 2; do
            sleep 0.05
            output=$(kdotool search 2>/dev/null)
            exit_code=$?
            if [[ $exit_code -ne 0 ]]; then
                ((hard_failures++))
                ((exit_failures++))
                if (( ${#failure_log[@]} < max_logged )); then
                    failure_log+=("  +${elapsed}ms  EXIT_FAIL post-retry-$retry_idx  code=$exit_code")
                fi
                output=""
                break
            fi
            [[ -n "$output" ]] && break
        done
        if [[ $exit_code -ne 0 ]]; then
            sleep "$poll_interval"
            continue
        fi
        if [[ -z "$output" ]]; then
            ((hard_failures++))
            ((empty_after_retry++))
            if (( ${#failure_log[@]} < max_logged )); then
                failure_log+=("  +${elapsed}ms  EMPTY post-retries (sustained empty after 2 retries)")
            fi
            sleep "$poll_interval"
            continue
        fi
    fi

    # Partial check — telemetry only, not a hard failure
    local -A current_set=()
    local current_count=0
    local line
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            current_set["$line"]=1
            ((current_count++))
        fi
    done <<< "$output"

    local missing_count=0
    for uuid in "${baseline_uuids[@]}"; do
        if [[ ! -v current_set[$uuid] ]]; then
            ((missing_count++))
        fi
    done
    unset current_set

    if [[ $missing_count -gt 0 ]]; then
        ((partial_responses++))
    fi

    sleep "$poll_interval"
done

# ============================================================================
# Results
# ============================================================================

local partial_rate="0.00"
local empty_rate="0.00"
if (( total_polls > 0 )); then
    partial_rate=$(awk -v p="$partial_responses" -v t="$total_polls" 'BEGIN { printf "%.2f", (p / t) * 100 }')
    empty_rate=$(awk -v e="$transient_empties" -v t="$total_polls" 'BEGIN { printf "%.2f", (e / t) * 100 }')
fi

if [[ $hard_failures -eq 0 ]]; then
    test_pass
    echo "    $total_polls polls, 0 hard failures"
    echo "    Transient empties (recovered): $transient_empties (${empty_rate}%)"
    echo "    Partial responses (telemetry): $partial_responses (${partial_rate}%) — handled by caller-side validation"
else
    test_fail "$hard_failures/$total_polls polls had hard failures (exit_fail or sustained empty)"
    echo "    Exit failures:                 $exit_failures"
    echo "    Empty after retry (sustained): $empty_after_retry"
    echo "    Transient empties (recovered): $transient_empties (${empty_rate}%)"
    echo "    Partial responses (telemetry): $partial_responses (${partial_rate}%)"
    echo ""
    echo "    Failure details (first $max_logged):"
    local detail
    for detail in "${failure_log[@]}"; do
        echo "$detail"
    done
    if (( hard_failures > max_logged )); then
        echo "    ... and $(( hard_failures - max_logged )) more"
    fi
    gate_failed
fi

}
_run_test_04
