#!/usr/bin/env python3
"""Compute dependency layers for a Swift package collection JSON file.

Reads a collection JSON (e.g. `collection.json`) with the schema used by
the Intrusive Memory package collection, extracts each package's
intra-org dependencies, and emits a JSON plan describing which packages
can run in parallel (same layer) and which must wait for upstream layers.

Usage:
    python compute_layers.py \
        --collection /path/to/collection.json \
        [--packages pkg1,pkg2,...] \
        [--with-dependents] \
        [--projects-root ~/Projects] \
        [--org intrusive-memory]

The collection file MUST be JSON. Other formats are not supported.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict, deque
from typing import Dict, Iterable, List, Set, Tuple


def load_collection(path: str) -> dict:
    if not path.lower().endswith(".json"):
        sys.exit(
            f"Error: collection file must be JSON (got: {path}). "
            "package-iterator only supports JSON collection files."
        )
    try:
        with open(path, "r") as f:
            return json.load(f)
    except FileNotFoundError:
        sys.exit(f"Error: collection file not found: {path}")
    except json.JSONDecodeError as e:
        sys.exit(f"Error: collection file is not valid JSON: {path}\n  {e}")


def package_name_from_url(url: str) -> str:
    base = url.rsplit("/", 1)[-1]
    if base.endswith(".git"):
        base = base[:-4]
    return base


def extract_graph(
    collection: dict, org: str
) -> Tuple[Set[str], Dict[str, Set[str]]]:
    """Return (nodes, edges) for intra-org dependencies.

    `edges[p]` is the set of packages `p` depends on.
    """
    nodes: Set[str] = set()
    for pkg in collection.get("packages", []):
        nodes.add(package_name_from_url(pkg["url"]))

    edges: Dict[str, Set[str]] = {n: set() for n in nodes}
    org_prefix = f"{org}/"
    for pkg in collection.get("packages", []):
        name = package_name_from_url(pkg["url"])
        deps = pkg.get("dependencies", {}) or {}
        for dep_ref in deps.keys():
            if dep_ref.startswith(org_prefix):
                dep_name = dep_ref[len(org_prefix):]
                # Only track deps that are also in the collection; untracked
                # external-to-collection siblings are noted but not graphed.
                if dep_name in nodes:
                    edges[name].add(dep_name)
    return nodes, edges


def compute_layers(
    nodes: Set[str], edges: Dict[str, Set[str]]
) -> List[List[str]]:
    """Kahn-style layered topological sort.

    Layer 0 = packages with no intra-org deps.
    Layer N+1 = packages whose deps are all in layers 0..N.
    """
    remaining: Dict[str, Set[str]] = {n: set(edges.get(n, set())) for n in nodes}
    placed: Set[str] = set()
    layers: List[List[str]] = []
    while remaining:
        ready = sorted(n for n, deps in remaining.items() if not (deps - placed))
        if not ready:
            cycle = sorted(remaining.keys())
            sys.exit(
                f"Error: dependency cycle detected among: {cycle}. "
                "Fix the collection before iterating."
            )
        layers.append(ready)
        placed.update(ready)
        for n in ready:
            del remaining[n]
    return layers


def reverse_deps_map(edges: Dict[str, Set[str]]) -> Dict[str, List[str]]:
    """For each package, list the packages that depend on it (direct only)."""
    rev: Dict[str, Set[str]] = defaultdict(set)
    for pkg, deps in edges.items():
        for d in deps:
            rev[d].add(pkg)
    return {k: sorted(v) for k, v in rev.items()}


def transitive_dependents(
    seeds: Iterable[str], edges: Dict[str, Set[str]]
) -> Set[str]:
    rev: Dict[str, Set[str]] = defaultdict(set)
    for pkg, deps in edges.items():
        for d in deps:
            rev[d].add(pkg)
    expanded: Set[str] = set(seeds)
    frontier: deque = deque(seeds)
    while frontier:
        pkg = frontier.popleft()
        for dependent in rev.get(pkg, set()):
            if dependent not in expanded:
                expanded.add(dependent)
                frontier.append(dependent)
    return expanded


def filter_layers(
    layers: List[List[str]], keep: Set[str]
) -> List[List[str]]:
    filtered = [[p for p in layer if p in keep] for layer in layers]
    return [layer for layer in filtered if layer]


def resolve_library_paths(
    packages: Iterable[str], projects_root: str
) -> Dict[str, str]:
    root = os.path.abspath(os.path.expanduser(projects_root))
    return {p: os.path.join(root, p) for p in packages}


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Compute dependency layers for a Swift package collection JSON file."
    )
    ap.add_argument(
        "--collection",
        required=True,
        help="Path to collection JSON file. Must have a .json extension.",
    )
    ap.add_argument(
        "--packages",
        default="",
        help="Comma- or space-separated subset (default: every package).",
    )
    ap.add_argument(
        "--with-dependents",
        action="store_true",
        help="Expand the subset to include transitive downstream packages.",
    )
    ap.add_argument(
        "--projects-root",
        default=os.path.expanduser("~/Projects"),
        help="Directory where library clones live as siblings (default: ~/Projects).",
    )
    ap.add_argument(
        "--org",
        default="intrusive-memory",
        help="GitHub org prefix used to identify intra-org deps (default: intrusive-memory).",
    )
    args = ap.parse_args()

    collection = load_collection(args.collection)
    nodes, edges = extract_graph(collection, args.org)
    if not nodes:
        sys.exit(
            "Error: no packages found in the collection. "
            "Expected a top-level `packages` array with entries that have a `url` field."
        )
    all_layers = compute_layers(nodes, edges)
    rev = reverse_deps_map(edges)

    raw_subset = [p for p in args.packages.replace(",", " ").split() if p]
    if raw_subset:
        subset = set(raw_subset)
        unknown = subset - nodes
        if unknown:
            sys.exit(
                f"Error: unknown packages (not in collection): {sorted(unknown)}"
            )
        if args.with_dependents:
            subset = transitive_dependents(subset, edges)
        layers = filter_layers(all_layers, subset)
    else:
        layers = all_layers

    all_pkgs = [p for layer in layers for p in layer]
    paths = resolve_library_paths(all_pkgs, args.projects_root)

    json.dump(
        {
            "collection_path": os.path.abspath(args.collection),
            "collection_revision": collection.get("revision"),
            "org": args.org,
            "layers": layers,
            "library_paths": paths,
            "reverse_deps": {k: v for k, v in rev.items() if k in all_pkgs},
        },
        sys.stdout,
        indent=2,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
