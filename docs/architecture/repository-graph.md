# Repository graph

The repository graph is generated directly from the repository.

## Generator

```text
scripts/bin/repo-graph.py
```

## Outputs

```text
assets/diagrams/repository-graph.json
assets/diagrams/repository-graph.mmd
```

The JSON file is the machine-readable source for future integrations.

The Mermaid file is the human-readable representation.

## Detected relations

- `uses`: Bash scripts sourcing shared libraries;
- `links_to`: relative Markdown links to repository files.

## Node types

- provider;
- operator;
- library;
- tooling;
- documentation;
- standard;
- template;
- test;
- file.

## Usage

From the repository root:

```bash
python3 scripts/bin/repo-graph.py
```

Include directories:

```bash
python3 scripts/bin/repo-graph.py --include-directories
```

Use a different output directory:

```bash
python3 scripts/bin/repo-graph.py --output-dir /tmp/proxmox-graph
```

## Validation

```bash
python3 -m py_compile scripts/bin/repo-graph.py
python3 scripts/bin/repo-graph.py
```

## Viewing the graph

The generator produces a Mermaid graph (`.mmd`).

On macOS, the generated file can be viewed directly with **MarkChart**.

Some IDEs and Mermaid extensions may treat `.mmd` files as plain text or may not render very large graphs correctly.

