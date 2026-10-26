#!/usr/bin/env bash
# Regenerates the recompiled C (src/recomp/gen) from your own default.xbe and
# applies this repository's patches to it. Nothing it writes is committed:
# build/xr and src/recomp/gen are .gitignored, the tool ships, the output
# doesn't.
#
#   xbe_parser    section layout             -> build/xr/parser
#   disasm        all code sections, with this repository's seed functions
#                 (seed_functions.json: entry points the static pass misses,
#                 found by running the game)  -> build/xr/disasm
#   recomp        emits the C                -> src/recomp/gen
#   patches/apply.py                          the game patches (patches/README.md)
#
# Two checkouts of the toolkit, as the port was built (see README.md):
#   XBOXRECOMP       sp00nznet/xboxrecomp, for xbe_parser and disasm. Its
#                    disassembler finds 10,627 functions here; the fork's
#                    finds about 180 fewer.
#   XBOXRECOMP_APEX  apexJCL/xboxrecomp (the D3D11 backend), for recomp: the
#                    generated C has to match the runtime it links against.
#
# Usage: ./regen.sh
# Environment: GAME (default game/Kung Fu Chaos), XBOXRECOMP (../xboxrecomp),
#              XBOXRECOMP_APEX (../xboxrecomp-apex), PYTHON (python, needs capstone).

set -euo pipefail

KFC="$(cd "$(dirname "$0")" && pwd)"
GAME="${GAME:-$KFC/game/Kung Fu Chaos}"
XBE="$GAME/default.xbe"
XBOXRECOMP="${XBOXRECOMP:-$KFC/../xboxrecomp}"
XBOXRECOMP_APEX="${XBOXRECOMP_APEX:-$KFC/../xboxrecomp-apex}"
PYTHON="${PYTHON:-python}"
OUT="$KFC/build/xr"
GEN="$KFC/src/recomp/gen"

# Absolute paths: the toolkit steps run from inside the toolkit checkouts.
[[ -d "$GAME" ]] && GAME="$(cd "$GAME" && pwd)" && XBE="$GAME/default.xbe"
[[ -d "$XBOXRECOMP" ]] && XBOXRECOMP="$(cd "$XBOXRECOMP" && pwd)"
[[ -d "$XBOXRECOMP_APEX" ]] && XBOXRECOMP_APEX="$(cd "$XBOXRECOMP_APEX" && pwd)"
if [[ ! -f "$XBE" ]]; then
    echo "default.xbe not found at $XBE"
    echo "Copy your own Kung Fu Chaos (NTSC-U) disc contents to game/Kung Fu Chaos, or set GAME."
    exit 1
fi
for d in "$XBOXRECOMP" "$XBOXRECOMP_APEX"; do
    [[ -d "$d/tools" ]] || { echo "toolkit not found: $d"; exit 1; }
done
mkdir -p "$OUT/parser" "$OUT/disasm" "$OUT/func_id" "$OUT/abi" "$OUT/recomp"

echo "== xbe_parser"
(cd "$XBOXRECOMP" && "$PYTHON" -m tools.xbe_parser "$XBE" --json "$OUT/parser/xbe_analysis.json" \
    > "$OUT/parser/xbe_parser.txt")

echo "== disasm"
(cd "$XBOXRECOMP" && "$PYTHON" -m tools.disasm "$XBE" --analysis-json "$OUT/parser/xbe_analysis.json" \
    -o "$OUT/disasm" --seed-functions "$KFC/seed_functions.json" --force > "$OUT/disasm/log.txt" 2>&1)

echo "== recomp"
rm -rf "$GEN"
(cd "$XBOXRECOMP_APEX" && "$PYTHON" -m tools.recomp "$XBE" --game-name "Kung Fu Chaos" --all --split 1000 \
    -o "$OUT/recomp" --gen-dir "$GEN" \
    --disasm-dir "$OUT/disasm" --func-id-dir "$OUT/func_id" --abi-dir "$OUT/abi" \
    > "$OUT/recomp.log" 2>&1)
grep -E "functions \(|unimplemented|unresolved" "$OUT/recomp.log" || true

echo "== patches"
"$PYTHON" "$KFC/patches/apply.py" "$GEN"

echo "== done: build with build.bat"
