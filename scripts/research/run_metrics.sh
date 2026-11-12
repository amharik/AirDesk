#!/bin/bash

research_annotate_process_metrics() {
    local json_path="$1"
    local time_path="$2"
    local host_model="$3"
    local cpu_brand="$4"
    local memory_bytes="$5"
    local real user system peak cpu_percent

    read -r real _ user _ system _ < "$time_path"
    peak="$(awk '/maximum resident set size/ { print $1; exit }' "$time_path")"
    peak="${peak:-0}"
    cpu_percent="$(awk -v real="$real" -v user="$user" -v system="$system" \
        'BEGIN { if (real > 0) printf "%.3f", ((user + system) / real) * 100; else print "null" }')"

    jq \
        --argjson cpu_percent "$cpu_percent" \
        --argjson peak_memory_bytes "$peak" \
        --arg host_model "$host_model" \
        --arg cpu_brand "$cpu_brand" \
        --argjson memory_bytes "$memory_bytes" \
        '.metrics.cpu_percent = $cpu_percent
        | .metrics.peak_memory_bytes = $peak_memory_bytes
        | .environment.host_model = $host_model
        | .environment.cpu = $cpu_brand
        | .environment.memory_bytes = $memory_bytes' \
        "$json_path" > "$json_path.tmp"
    mv "$json_path.tmp" "$json_path"
}
