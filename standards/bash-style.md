# Bash Style Guide

## Interpreter

Use:

```bash
#!/usr/bin/env bash
```

## Strict mode

Operational scripts should normally use:

```bash
set -Eeuo pipefail
```

Audit scripts may relax `errexit` only where failures are explicitly handled.

## Structure

Each executable script should contain:

1. metadata header;
2. constants;
3. shared library imports;
4. functions;
5. `main`;
6. `main "$@"`.

Example:

```bash
main() {
    require_root
    require_command qm
}

main "$@"
```

Avoid executable code outside functions, except constants and library imports.

## Variables

Use lowercase names for local variables:

```bash
local vmid
local config
```

Use uppercase names only for constants and exported configuration:

```bash
readonly SCRIPT_NAME="pve-host-audit.sh"
```

Always quote variable expansions:

```bash
"$vmid"
"${array[@]}"
```

## Conditions

Prefer:

```bash
[[ ... ]]
```

over:

```bash
[ ... ]
```

Use arithmetic expressions for numbers:

```bash
(( usage >= 85 ))
```

## Functions

Functions should:

- perform one clear task;
- use local variables;
- return meaningful exit codes;
- avoid modifying global state unless intentional.

Use names such as:

```bash
require_root
print_section
get_vm_config
```

## Error handling

Errors must be written to standard error:

```bash
printf 'Error: %s\n' "$message" >&2
```

Use the shared logging and validation libraries when available.

## Temporary files

Create temporary files with:

```bash
tmp_file=$(mktemp)
```

Remove them with a trap:

```bash
trap 'rm -f "$tmp_file"' EXIT
```

## Read-only audits

Scripts under `scripts/audit/` must not:

- call `qm set`;
- call `qm destroy`;
- modify storage;
- install or remove packages;
- restart services;
- change configuration files.

## Destructive operations

Scripts that modify systems should support:

```text
--report
--dry-run
--apply
```

where practical.

Destructive actions must never be the default.

## Dependencies

Validate every external command:

```bash
require_command qm
require_command pveversion
```

## Output

Use the shared functions in:

```text
scripts/lib/colors.sh
scripts/lib/output.sh
scripts/lib/logging.sh
scripts/lib/validation.sh
```

## Static analysis

All scripts should pass:

```bash
shellcheck path/to/script.sh
```
