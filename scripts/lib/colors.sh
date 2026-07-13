#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# This file is a sourced library. The color variables are consumed by
# other scripts after sourcing and therefore appear unused to ShellCheck
# when this file is checked in isolation.

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    readonly COLOR_RED=$'\033[31m'
    readonly COLOR_GREEN=$'\033[32m'
    readonly COLOR_YELLOW=$'\033[33m'
    readonly COLOR_BLUE=$'\033[34m'
    readonly COLOR_CYAN=$'\033[36m'
    readonly COLOR_BOLD=$'\033[1m'
    readonly COLOR_RESET=$'\033[0m'
else
    readonly COLOR_RED=""
    readonly COLOR_GREEN=""
    readonly COLOR_YELLOW=""
    readonly COLOR_BLUE=""
    readonly COLOR_CYAN=""
    readonly COLOR_BOLD=""
    readonly COLOR_RESET=""
fi
