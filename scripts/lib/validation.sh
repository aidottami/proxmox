#!/usr/bin/env bash

require_root() {
    if ((EUID != 0)); then
        log_error "This command must be run as root."
        exit 1
    fi
}

require_command() {
    local command_name=$1

    if ! command -v "$command_name" >/dev/null 2>&1; then
        log_error "Required command not found: $command_name"
        exit 2
    fi
}

require_file() {
    local file_path=$1

    if [[ ! -f "$file_path" ]]; then
        log_error "Required file not found: $file_path"
        exit 2
    fi
}

require_directory() {
    local directory_path=$1

    if [[ ! -d "$directory_path" ]]; then
        log_error "Required directory not found: $directory_path"
        exit 2
    fi
}

require_positive_integer() {
    local value=$1
    local name=${2:-value}

    if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
        log_error "$name must be a positive integer: $value"
        exit 1
    fi
}
