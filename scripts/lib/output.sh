#!/usr/bin/env bash

status_ok() {
    printf '%s✔%s' "$COLOR_GREEN" "$COLOR_RESET"
}

status_warning() {
    printf '%s⚠%s' "$COLOR_YELLOW" "$COLOR_RESET"
}

status_error() {
    printf '%s✘%s' "$COLOR_RED" "$COLOR_RESET"
}

print_title() {
    local title=$1

    printf '%s============================================================%s\n' \
        "$COLOR_BLUE" "$COLOR_RESET"
    printf '%s%s%s\n' "$COLOR_BOLD" "$title" "$COLOR_RESET"
    printf '%s============================================================%s\n' \
        "$COLOR_BLUE" "$COLOR_RESET"
}

print_section() {
    local title=$1

    printf '\n%s%s%s\n' "$COLOR_BOLD" "$title" "$COLOR_RESET"
    printf '%*s\n' "${#title}" '' | tr ' ' '-'
}

print_value() {
    local label=$1
    local value=$2

    printf '%-24s %s\n' "$label" "$value"
}
