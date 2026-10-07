#!/usr/bin/env bash
# Rebuilds the ability place, Jajanken.rbxl (the M1 string, Gon's Jajanken + Killua's lightning, the
# parry system, the ability menu, a test area with training dummies), and the labelled kits:
# Jajanken.rbxm, ../Killua/Killua.rbxm and ../Melee/Melee.rbxm.
#   ./build.sh path/to/ANIMSFORCLAUDE.rbxmx path/to/nen.rbxmx [path/to/rbxconv]
# Needs Python 3 + numpy, Rojo 7.4+ (https://rojo.space) and, for the .rbxm files, an rbxmx -> rbxm
# converter (any rbx-dom based tool; pass it as the third argument).
set -euo pipefail
cd "$(dirname "$0")"
python3 ../Killua/generate_killua.py "$1" "$2" # builds ../Combat and ../Loadout too
python3 ../Melee/generate_melee.py "$1" "$2"
python3 generate_jajanken.py "$1" "$2"
rojo build place.project.json -o Jajanken.rbxl
if [[ -n "${3:-}" ]]; then
  "$3" Jajanken.rbxmx Jajanken.rbxm
  "$3" ../Killua/Killua.rbxmx ../Killua/Killua.rbxm
  "$3" ../Melee/Melee.rbxmx ../Melee/Melee.rbxm
fi
echo "Built Jajanken.rbxl"
