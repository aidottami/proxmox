#!/usr/bin/env bash

join_by() {
    local delimiter=$1
    shift

    local first=1
    local item

    for item in "$@"; do
        if ((first)); then
            printf '%s' "$item"
            first=0
        else
            printf '%s%s' "$delimiter" "$item"
        fi
    done
}

is_terminal() {
    [[ -t 1 ]]
}

command_output_or_empty() {
    local command_name=$1
    shift

    "$command_name" "$@" 2>/dev/null || true
}
