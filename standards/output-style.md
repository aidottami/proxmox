# Output Style

## Main title

```text
============================================================
PVE HOST AUDIT
============================================================
```

## Sections

```text
HOST
----
```

## Status symbols

```text
✔  healthy or compliant
⚠  warning or informational deviation
✘  error or action required
```

## Status levels

- `OK`: healthy
- `INFO`: relevant but not problematic
- `WARNING`: attention recommended
- `ERROR`: action required

## Column layout

Labels should use a consistent width:

```text
Kernel in uso            7.0.14-4-pve
QEMU Agent disabilitato  2
```

Tables should contain explicit headers:

```text
VMID   NAME                           DETAIL
-----  ------------------------------ ------------------------
```

## Colors

Colors may be used only when output is connected to a terminal.

They must be disabled when:

```bash
NO_COLOR=1
```

or when standard output is not a terminal.

## Redirection

Scripts must remain readable when redirected:

```bash
NO_COLOR=1 script.sh > report.txt
```

## Summary

Audit scripts should end with:

```text
Audit completed. No changes were made.
```

Operational scripts should state exactly what was changed.
