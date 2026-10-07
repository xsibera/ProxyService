#!/usr/bin/env bash
# Rebuilds the ability place, Jajanken.rbxl (the M1 string, sprinting and rolling, Gon's Jajanken +
# Killua's lightning, the parry system, the ability menu, and the map: a Whale Island village with
# a training yard and a bandit camp), and the labelled kits: Jajanken.rbxm, ../Killua/Killua.rbxm,
# ../Melee/Melee.rbxm and ../Movement/Movement.rbxm.
#   ./build.sh path/to/ANIMSFORCLAUDE.rbxmx path/to/nen.rbxmx [path/to/rbxconv]
# Needs Python 3 + numpy, Rojo 7.4+ (https://rojo.space) and, for the .rbxm files, an rbxmx -> rbxm
# converter (any rbx-dom based tool; pass it as the third argument).
set -euo pipefail
cd "$(dirname "$0")"
python3 ../Killua/generate_killua.py "$1" "$2" # builds ../Combat and ../Loadout too
python3 ../Melee/generate_melee.py "$1" "$2"
python3 ../Movement/generate_movement.py "$1" "$2"
python3 generate_jajanken.py "$1" "$2"
python3 ../Village/generate_village.py "$1" # last: it stands the other packages' rigs in its training yard
rojo build place.project.json -o Jajanken.rbxl
if [[ -n "${3:-}" ]]; then
  "$3" Jajanken.rbxmx Jajanken.rbxm
  "$3" ../Killua/Killua.rbxmx ../Killua/Killua.rbxm
  "$3" ../Melee/Melee.rbxmx ../Melee/Melee.rbxm
  "$3" ../Movement/Movement.rbxmx ../Movement/Movement.rbxm
fi
echo "Built Jajanken.rbxl"
