#!/usr/bin/env bash
# Rebuilds Place1.rbxlx from source. Needs Rojo 7.4+ (https://rojo.space) and Python 3.
#   ./build.sh            regenerate the world + build the place
#   ./build.sh --anims    also re-solve the animation IK (needs numpy)
set -euo pipefail
cd "$(dirname "$0")"
if [[ "${1:-}" == "--anims" ]]; then
  python3 tools/build_animations.py
fi
python3 tools/build_world.py
rojo build -o Place1.rbxlx
python3 tools/strip_rojo_attrs.py Place1.rbxlx
echo "Built Place1.rbxlx"
