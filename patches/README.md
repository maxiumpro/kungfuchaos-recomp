# Patches to the generated C

`regen.sh` deletes and rewrites `src/recomp/gen`, then runs **`apply.py`** on it, so these come back on
every regeneration. By hand: `python patches/apply.py [gen directory]`. A file that already has them is
left alone; if the original code is not what the script expects (a lifter change), it stops and names
the line it could not find instead of leaving a patch half applied.

Checked 2026-10-23: a clean regeneration plus `apply.py` is byte-identical to the hand-patched code.

Addresses are from the NTSC-U `default.xbe`.

## True progressive matches (480 lines)

Kung Fu Chaos renders its menus at 640x480 but sets every match up as 640x240 *fields*: half the lines,
alternating between frames, as an interlaced TV shows them. Shown on a progressive screen that is a
picture that bobs up and down by half a line, or a combed one if the fields are woven. The patch makes
the match render full frames:

- `kfc_progressive()` (a helper placed before `sub_000C6E30`): on by default,
  `RECOMP_KFC_PROGRESSIVE=0` gives the console's fields back.
- `sub_000C6E30` (the match's video setup): `BackBufferHeight` (`[esi+0x24]`) 0xF0 -> 0x1E0
  (0x120 -> 0x240 for PAL), and no `D3DPRESENTFLAG_FIELD` (`| 0x80`). `MEM8(0x3821BC) = 1` stays:
  it means "in a match", not "fields" (clearing it loses the HUD).
- Right before `call sub_002B9590` (`D3DDevice_Reset`): the game hands Reset its own surface headers
  (`PP.BufferSurfaces[0..1]` and `PP.DepthStencilSurface`, at `esi+0xE8`, `+0x100`, `+0x118`) set up as
  640x240. Their memory already holds 640x480, so only the height in each header's size word (+0x10)
  changes, 239 -> 479.
- `sub_000C7070`: the -0.5 line offset it puts on alternate fields (`MEM32(esp+4) = 0xBF000000`) is
  0 when progressive.

To add a patch: one more entry in `PATCHES` (function, original text, patched text).
