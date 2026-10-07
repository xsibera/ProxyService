#!/usr/bin/env bash
# Rebuilds Jajanken.rbxl (the test place) and Jajanken.rbxm (the labelled kit).
#   ./build.sh path/to/ANIMSFORCLAUDE.rbxmx path/to/nen.rbxmx [path/to/rbxconv]
# Needs Python 3 + numpy, Rojo 7.4+ (https://rojo.space) and, for the .rbxm, an rbxmx -> rbxm
# converter (any rbx-dom based tool; pass it as the third argument).
set -euo pipefail
cd "$(dirname "$0")"
python3 generate_jajanken.py "$1" "$2"
rojo build place.project.json -o Jajanken.rbxl
if [[ -n "${3:-}" ]]; then
  "$3" Jajanken.rbxmx Jajanken.rbxm
fi
echo "Built Jajanken.rbxl"
