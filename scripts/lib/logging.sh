#!/usr/bin/env bash

log_info() {
    printf '%sINFO%s  %s\n' "$COLOR_CYAN" "$COLOR_RESET" "$*"
}

log_success() {
    printf '%sOK%s    %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*"
}

log_warning() {
    printf '%sWARN%s  %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2
}

log_error() {
    printf '%sERROR%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2
}

log_debug() {
    [[ "${DEBUG:-0}" == "1" ]] || return 0
    printf 'DEBUG %s\n' "$*" >&2
}
