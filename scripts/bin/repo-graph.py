#!/usr/bin/env python3
"""Generate JSON and Mermaid graphs for the repository."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

IGNORED_DIRECTORIES = {
    ".git", ".github", ".idea", ".venv", ".vscode",
    "__pycache__", "node_modules", "vendor",
}
IGNORED_FILES = {".DS_Store"}

SOURCE_PATTERN = re.compile(r'^\s*(?:source|\.)\s+["\']?([^"\'#\s]+)', re.MULTILINE)
MARKDOWN_LINK_PATTERN = re.compile(r'\[[^\]]+\]\((?!https?://|mailto:|#)([^)#]+)(?:#[^)]+)?\)')


@dataclass(frozen=True)
class Node:
    id: str
    path: str
    name: str
    kind: str
    category: str
    extension: str | None


@dataclass(frozen=True)
class Edge:
    source: str
    target: str
    relation: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate JSON and Mermaid graphs for the repository."
    )
    parser.add_argument("--root", type=Path, default=None)
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--include-directories", action="store_true")
    return parser.parse_args()


def find_repo_root(start: Path) -> Path:
    current = start.resolve()
    for candidate in (current, *current.parents):
        if (candidate / ".git").exists():
            return candidate
    raise RuntimeError("Unable to locate a Git repository root.")


def should_ignore(path: Path, root: Path) -> bool:
    relative = path.relative_to(root)
    if any(part in IGNORED_DIRECTORIES for part in relative.parts):
        return True
    return path.name in IGNORED_FILES


def node_id(path: Path, root: Path) -> str:
    relative = path.relative_to(root).as_posix()
    normalized = re.sub(r"[^A-Za-z0-9_]+", "_", relative).strip("_")
    return f"node_{normalized or 'root'}"


def classify(path: Path, root: Path) -> tuple[str, str]:
    relative = path.relative_to(root)
    parts = relative.parts

    if path.is_dir():
        return "directory", parts[0] if parts else "root"

    suffix = path.suffix.lower()

    if suffix == ".sh":
        if len(parts) >= 2 and parts[0] == "scripts":
            if parts[1] == "audit":
                return "provider", "audit"
            if parts[1] == "lib":
                return "library", "lib"
            if parts[1] == "bin":
                return "tooling", "bin"
            return "operator", parts[1]
        return "shell-script", parts[0] if parts else "root"

    if suffix == ".py":
        return "tooling", parts[1] if len(parts) > 1 else "python"

    if suffix in {".md", ".markdown"}:
        if parts and parts[0] == "standards":
            return "standard", "standards"
        if parts and parts[0] == "docs":
            return "documentation", parts[1] if len(parts) > 1 else "docs"
        return "documentation", parts[0] if parts else "root"

    if parts and parts[0] == "templates":
        return "template", parts[1] if len(parts) > 1 else "templates"

    if "test" in path.stem.lower():
        return "test", parts[1] if len(parts) > 1 else "tests"

    return "file", parts[0] if parts else "root"


def iter_paths(root: Path, include_directories: bool) -> Iterable[Path]:
    for path in sorted(root.rglob("*")):
        if should_ignore(path, root):
            continue
        if path.is_dir() and not include_directories:
            continue
        yield path


def build_nodes(root: Path, include_directories: bool) -> list[Node]:
    nodes: list[Node] = []
    for path in iter_paths(root, include_directories):
        kind, category = classify(path, root)
        nodes.append(
            Node(
                id=node_id(path, root),
                path=path.relative_to(root).as_posix(),
                name=path.name,
                kind=kind,
                category=category,
                extension=path.suffix.lower() or None,
            )
        )
    return nodes


def resolve_reference(raw_reference: str, source_file: Path, root: Path) -> Path | None:
    reference = raw_reference.strip()
    replacements = {
        "$REPO_ROOT": str(root),
        "${REPO_ROOT}": str(root),
        "$SCRIPT_DIR": str(source_file.parent),
        "${SCRIPT_DIR}": str(source_file.parent),
    }
    for variable, replacement in replacements.items():
        reference = reference.replace(variable, replacement)

    candidate = Path(reference)
    if not candidate.is_absolute():
        candidate = source_file.parent / candidate

    try:
        resolved = candidate.resolve()
        resolved.relative_to(root)
    except (OSError, ValueError):
        return None

    return resolved if resolved.exists() else None


def build_edges(root: Path, nodes: list[Node]) -> list[Edge]:
    id_by_path = {
        (root / node.path).resolve(): node.id
        for node in nodes
        if node.kind != "directory"
    }
    edges: set[Edge] = set()

    for node in nodes:
        source_path = (root / node.path).resolve()
        if not source_path.is_file():
            continue

        try:
            text = source_path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue

        if source_path.suffix == ".sh":
            for match in SOURCE_PATTERN.finditer(text):
                target_path = resolve_reference(match.group(1), source_path, root)
                if target_path and target_path in id_by_path:
                    edges.add(Edge(node.id, id_by_path[target_path], "uses"))

        if source_path.suffix.lower() in {".md", ".markdown"}:
            for match in MARKDOWN_LINK_PATTERN.finditer(text):
                target_path = resolve_reference(match.group(1), source_path, root)
                if target_path and target_path in id_by_path:
                    edges.add(Edge(node.id, id_by_path[target_path], "links_to"))

    return sorted(edges, key=lambda edge: (edge.source, edge.relation, edge.target))


def graph_payload(root: Path, nodes: list[Node], edges: list[Edge]) -> dict:
    counts: dict[str, int] = {}
    for node in nodes:
        counts[node.kind] = counts.get(node.kind, 0) + 1

    return {
        "schema_version": "1.0",
        "repository": root.name,
        "root": str(root),
        "summary": {
            "nodes": len(nodes),
            "edges": len(edges),
            "node_kinds": dict(sorted(counts.items())),
        },
        "nodes": [asdict(node) for node in nodes],
        "edges": [asdict(edge) for edge in edges],
    }


def build_mermaid(nodes: list[Node], edges: list[Edge]) -> str:
    class_map = {
        "provider": "provider",
        "operator": "operator",
        "library": "library",
        "tooling": "tooling",
        "documentation": "documentation",
        "standard": "standard",
        "template": "template",
        "test": "test",
        "directory": "directory",
    }

    lines = [
        "flowchart LR",
        "",
        "    classDef provider fill:#dff5e1,stroke:#277a35;",
        "    classDef operator fill:#fff0d6,stroke:#a56200;",
        "    classDef library fill:#e5edff,stroke:#3157a4;",
        "    classDef tooling fill:#efe4ff,stroke:#7041a6;",
        "    classDef documentation fill:#f2f2f2,stroke:#666;",
        "    classDef standard fill:#ffe6ee,stroke:#a43c61;",
        "    classDef template fill:#e4f7f7,stroke:#2f7777;",
        "    classDef test fill:#fff9d8,stroke:#8a7a00;",
        "    classDef directory fill:#ffffff,stroke:#999,stroke-dasharray: 3 3;",
        "    classDef file fill:#ffffff,stroke:#999;",
        "",
    ]

    for node in nodes:
        label = node.path.replace('"', '\\"')
        lines.append(f'    {node.id}["{label}"]')
        lines.append(f"    class {node.id} {class_map.get(node.kind, 'file')};")

    if edges:
        lines.append("")

    for edge in edges:
        relation = "uses" if edge.relation == "uses" else "links to"
        lines.append(f"    {edge.source} -->|{relation}| {edge.target}")

    lines.append("")
    return "\n".join(lines)


def write_outputs(output_dir: Path, payload: dict, mermaid: str) -> tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    json_path = output_dir / "repository-graph.json"
    mermaid_path = output_dir / "repository-graph.mmd"

    json_path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    mermaid_path.write_text(mermaid, encoding="utf-8")
    return json_path, mermaid_path


def main() -> int:
    args = parse_args()
    try:
        root = args.root.resolve() if args.root else find_repo_root(Path.cwd())
        output_dir = (
            args.output_dir.resolve()
            if args.output_dir
            else root / "assets" / "diagrams"
        )
        nodes = build_nodes(root, args.include_directories)
        edges = build_edges(root, nodes)
        payload = graph_payload(root, nodes, edges)
        json_path, mermaid_path = write_outputs(
            output_dir, payload, build_mermaid(nodes, edges)
        )
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"Repository: {root}")
    print(f"Nodes:      {len(nodes)}")
    print(f"Edges:      {len(edges)}")
    print(f"JSON:       {json_path}")
    print(f"Mermaid:    {mermaid_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
