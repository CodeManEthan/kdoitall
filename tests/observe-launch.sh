#!/bin/bash

# observe-launch.sh — Watch exactly what windows an app creates during startup.
# Usage: ./observe-launch.sh <app_id> [duration_seconds]
#
# Snapshots all windows before launch, then polls every 250ms, reporting
# every new window that appears and every tracked window that disappears.

app_id="${1:?Usage: $0 <app_id> [duration_seconds]}"
duration="${2:-30}"
poll_ms=250

echo "=== Observing launch: $app_id (${duration}s) ==="
echo ""

# --- Snapshot before launch ---
declare -A baseline_uuids
while IFS= read -r uuid; do
    [[ -n "$uuid" ]] && baseline_uuids["$uuid"]=1
done < <(kdotool search 2>/dev/null)

echo "[pre-launch] Baseline: ${#baseline_uuids[@]} windows"
echo ""

# --- Launch ---
launch_time=$(date +%s%3N)
gtk-launch "$app_id" &>/dev/null &
echo "[$(date +%H:%M:%S.%3N)] Launched $app_id"
echo ""

# --- Poll loop ---
declare -A seen_uuids       # uuid -> "class|title" at first sighting
declare -A appeared_at      # uuid -> timestamp ms
declare -A disappeared_at   # uuid -> timestamp ms
declare -A alive_uuids      # currently alive tracked (non-baseline) uuids

end_time=$(( $(date +%s%3N) + duration * 1000 ))

while (( $(date +%s%3N) < end_time )); do
    now=$(date +%s%3N)
    elapsed=$(( now - launch_time ))
    now_fmt=$(date +%H:%M:%S.%3N)

    # Get current window list
    declare -A current_uuids
    while IFS= read -r uuid; do
        [[ -n "$uuid" ]] && current_uuids["$uuid"]=1
    done < <(kdotool search 2>/dev/null)

    # Check for NEW windows (not in baseline, not yet seen)
    for uuid in "${!current_uuids[@]}"; do
        if [[ ! -v baseline_uuids[$uuid] && ! -v seen_uuids[$uuid] ]]; then
            class=$(kdotool getwindowclassname "$uuid" 2>/dev/null) || class=""
            title=$(kdotool getwindowname "$uuid" 2>/dev/null) || title=""
            seen_uuids["$uuid"]="${class}|${title}"
            appeared_at["$uuid"]=$elapsed
            alive_uuids["$uuid"]=1
            echo "[${now_fmt}] +${elapsed}ms  NEW      ${uuid}  class='${class}'  title='${title}'"
        fi
    done

    # Check for DISAPPEARED windows (was alive, no longer in current)
    for uuid in "${!alive_uuids[@]}"; do
        if [[ ! -v current_uuids[$uuid] ]]; then
            disappeared_at["$uuid"]=$elapsed
            unset alive_uuids["$uuid"]
            local_info="${seen_uuids[$uuid]}"
            lifespan=$(( elapsed - appeared_at[$uuid] ))
            echo "[${now_fmt}] +${elapsed}ms  GONE     ${uuid}  (lived ${lifespan}ms)  was: ${local_info}"
        fi
    done

    # Check for REAPPEARED windows (previously seen and died, now back)
    for uuid in "${!current_uuids[@]}"; do
        if [[ -v disappeared_at[$uuid] && ! -v alive_uuids[$uuid] ]]; then
            class=$(kdotool getwindowclassname "$uuid" 2>/dev/null) || class=""
            title=$(kdotool getwindowname "$uuid" 2>/dev/null) || title=""
            echo "[${now_fmt}] +${elapsed}ms  REAPPEAR ${uuid}  class='${class}'  title='${title}'  (was gone since +${disappeared_at[$uuid]}ms)"
            alive_uuids["$uuid"]=1
            unset disappeared_at["$uuid"]
            # Update sighting info
            seen_uuids["$uuid"]="${class}|${title}"
            appeared_at["$uuid"]=$elapsed
        fi
    done

    unset current_uuids
    sleep "$(printf '%d.%03d' "$((poll_ms / 1000))" "$((poll_ms % 1000))")"
done

# --- Summary ---
echo ""
echo "=== Summary ==="
echo ""
printf "%-40s  %-25s  %-20s  %s\n" "UUID" "CLASS" "APPEARED" "STATUS"
echo "──────────────────────────────────────────────────────────────────────────────────────────────────────────"
for uuid in "${!seen_uuids[@]}"; do
    IFS='|' read -r class title <<< "${seen_uuids[$uuid]}"
    appear="${appeared_at[$uuid]}ms"
    if [[ -v disappeared_at[$uuid] ]]; then
        lifespan=$(( disappeared_at[$uuid] - appeared_at[$uuid] ))
        status="GONE after ${lifespan}ms"
    else
        status="ALIVE"
    fi
    printf "%-40s  %-25s  +%-19s  %s\n" "$uuid" "$class" "$appear" "$status"
done
echo ""
echo "Still alive: ${#alive_uuids[@]} new window(s)"
