#!/bin/bash
CACHE_FILE="/dev/shm/gpu_stats.txt"

while true; do
    STATS=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,power.draw,memory.used,clocks.current.graphics --format=csv,noheader,nounits 2>/dev/null)
    if [ -n "$STATS" ]; then
        IFS=', ' read -r util temp power mem_used clock <<< "$STATS"
        power_int=${power%.*}
        echo "${util}% ${temp}°C ${power_int}W | VRAM ${mem_used}MB" > "${CACHE_FILE}.tmp"
        mv "${CACHE_FILE}.tmp" "${CACHE_FILE}"
    fi
    sleep 1
done
