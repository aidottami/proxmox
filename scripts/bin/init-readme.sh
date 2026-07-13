#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

declare -A DESC=(
    ["."]="Repository dedicato a Proxmox VE: script, documentazione, template e automazioni."
    ["scripts"]="Script Bash e strumenti di automazione."
    ["docs"]="Documentazione tecnica, how-to e note operative."
    ["templates"]="Template e configurazioni riutilizzabili."
    ["ansible"]="Playbook, ruoli e inventory Ansible."
    ["hooks"]="Hook script per Proxmox."
    ["examples"]="Esempi di configurazione e utilizzo."
)

for dir in "${!DESC[@]}"; do
    file="$dir/README.md"

    if [[ ! -f "$file" ]]; then
        title=$(basename "$dir")
        [[ "$dir" == "." ]] && title="Proxmox"

        cat >"$file" <<EOF
# $title

${DESC[$dir]}
EOF

        echo "Creato $file"
    else
        echo "Esiste già: $file"
    fi
done
