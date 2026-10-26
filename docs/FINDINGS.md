# What it took

Everything Kung Fu Chaos needed beyond the stock toolkit, with the evidence for each. Toolkit changes
live on the `kungfuchaos` branch of the D3D11 fork (see the README); the one game patch is in
`patches/`. Each change has an environment switch that turns it off, named in its entry.

Addresses are from the NTSC-U `default.xbe`.

## Bring-up

1. **D3D fence mirror.** `main.c` calls `xbox_Nv2aMirrorFence(0x002CA6A8, 0x2C, 0x30)`: the D3D device
   pointer and its fence offsets, the same as Burnout 3's.
2. **Seed functions.** 10 function entries the static disassembly misses (`seed_functions.json`, found with
   `tools.seed_from_log` from a run's log). Two of them, `0x209024` and `0x20E4EC`, were running through the
   interpreter fallback and held the game at 4 FPS.
3. **Disassembler.** The sp00nznet toolkit's `disasm` finds 10,627 functions here, the fork's about 180
   fewer; `regen.sh` disassembles with the first and lifts with the second.
4. **`rt_alias_check=0`** (`RECOMP_DEBUG`): the game draws 320x240 surfaces into the memory of a 640x480 one.
5. **Controller as player 1:** `RECOMP_USB_NDP=4`, `RECOMP_USB_PORT=2` (XAPI numbers ports 3, 4, 1, 2 as
   players 1 to 4).

## Kernel

6. **Heap: split large free blocks** (`heap_alloc_locked`, `xbox_memory_layout.c`). A freed block was handed
   whole to the next request, however small. Backing out of a loading screen with B frees the 6.8 MB
   streaming buffers; small requests then took them (15 MB of slack in the `[HEAP] exhausted` report), the
   reader's 6.8 MB `malloc` on the way back to the menu returned 0, `front_end_common.group` was left with an
   empty resource, and the next match crashed cloning or unloading it (`sub_001DAD95+0xB64`,
   `sub_001DD630+0x31C`). Now a block with at least 64 KB to spare is split (`heap_carve_block`) and the rest
   stays free. 3 of 3 unattended cancel-and-reenter runs without a crash, the large block reused at the same
   address. `RECOMP_HEAP_SPLIT=0` turns it off. (`RECOMP_HEAP_RECLAIM=1` also avoided the crash, at ~9 FPS.)
7. **Contiguous memory avoids "named" page numbers** (`contig_free_page`, `xbox_memory_layout.c`). One
   physical page number can name both a heap page (once the title asked for its `MmGetPhysicalAddress`) and a
   page of the contiguous allocator, and the APU resolves it to the heap one. Back at the menu the music is
   reloaded into contiguous memory; one of its pages landed on a number DirectSound had named for a sound
   still alive in the heap, and the APU played those bytes on every turn of the ring: a sharp noise every
   600 ms on character select. The allocator now skips such pages. Without: noise in 2 of 5 runs, a "named"
   page in the voice's ring; with: 0 of 3. `RECOMP_CONTIG_AVOID_NAMED=0` turns it off.
8. **`KeSetBasePriorityThread` / `KeQueryBasePriorityThread`** (`kernel_bridge.c`) passed the thread
   object's guest address on as a Windows `HANDLE`, so no title's thread priority was ever applied. Now the
   object is mapped to its host thread (`bridge_thread_host`).
9. **Vblank rate** (`RECOMP_VBLANK_HZ`, `kernel_pacing.c`, experimental): the vblank interrupt was fixed at
   60 Hz. Kung Fu Chaos times its logic with real time, so at 120 Hz the match clock (the HUD's dial, checked
   at +15/+20/+25 s), the match intro and the boot movies run at the same pace as at 60. Measured: 60 -> 60,
   120 -> 115-120, 144 -> 138 FPS.
10. **`XC_VIDEO`** (`RECOMP_XC_VIDEO`, `kernel_xbox.c`): the video flags setting can be set from the
    environment (720p, 1080i, 480p, widescreen...). Kung Fu Chaos ignores 720p/1080i and has no 480p mode for
    matches, which is why the progressive patch exists.

## Audio (APU)

11. **Silent frames while the title turns the SE off** (`apu_core.c`, frame thread). During a match the game
    sets `SECTL XCNTMODE` to off for one to four frames. The frame thread then took its "lightweight" branch,
    which advances the frame counter and hands the device 32 silent samples a frame: 32-128 samples of digital
    zero in the middle of the sound, always ending on a 256-sample period boundary (a click, worst after a
    special move). xemu produces no frame while the SE is off, as the fork already did for a trapped front
    end; now this case does the same, for up to 100 ms. Found with a one-byte-a-frame log (branch taken, any
    sound, voices) set against a WAV capture; the same match went from 11 holes to 0, with 0 device
    starvations. `RECOMP_APU_SE_OFF_HOLD_MS=0` turns it off.

## NV2A executor

12. **2D blits** (`nv2a_pb_exec.c`, `method_2d` / `blit_2d`). Nothing executed `NV_CONTEXT_SURFACES_2D`
    (NV062, subchannel 3) and `NV_IMAGE_BLIT` (NV09F, subchannel 2), XDK D3D's fixed binding for `CopyRects`.
    Kung Fu Chaos copies the 640x480 frame to `0x7E0000` every frame and uses it as a background texture: the
    intro, menus and pause were black, in the software renderer too. `RECOMP_BLIT_2D=0` turns them off.
13. **Present selection in a field mode** (`present_pick`). A surface narrower than the display mode cannot be
    what the CRTC scans (the match keeps a 320x240 target at the display pitch); and at twice the display
    pitch the CRTC scans fields of half the mode's height, so a full-height surface at that pitch is
    offscreen (the pause draws one 640x480 quad there, and that was shown instead of the menu).

## D3D11 backend

14. **2D blits on the GPU** (`d3d11_on_blit`, a new optional `on_blit` backend hook). A blit from a render
    target is copied GPU to GPU, into the destination render target when there is one (the director's
    projector shows the match through `0x330000`) or into a texture bound when that address is read.
    `RECOMP_D3D11_GPU_BLIT=0` turns it off.
15. **GPU copies written back when a texture reads their memory** (`bt_sync_for_texture`): once, and only if
    the guest has not written there since the copy (`bt_mem_sample` fingerprint). The pause copies the match
    frame once and keeps it as its background; after 2 flips it decoded the untouched bytes: black.
16. **Polygon offset** (`rasterizer_state`). The backend read `POLY_OFFSET_FILL_ENABLE`, `SCALE_FACTOR` and
    `BIAS` but never applied them. The carousel's thumbnails sit on the film strip at the same depth with
    `LEQUAL` and offset (-1, -4); without it they z-fought with the strip (a torn, jagged strip). Now
    `SlopeScaledDepthBias` / `DepthBias`, one state per combination. `RECOMP_D3D11_NO_POLY_OFFSET=1`.
17. **W-buffered depth** (`w_depth()`, `d3d8_combiners_hlsl.c`). The game asks for W-buffering
    (`SET_CONTROL0` bit 16, `Z_PERSPECTIVE_ENABLE`) and does depth of field with it: it copies the frame to
    320x240, blurs it, and draws it back over the frame as three full-screen quads with `LEQUAL` at w = 690k,
    789k and 888k (z = w / 16777215), so only far pixels are blurred. The backend stored z/w (~0.97 for the
    whole scene): every pixel was behind those quads and the whole match came out blurred and ghosted. Now the
    combiner shader writes `SV_Depth = SV_Position.w / 16777215` (or / 65535 on Z16) when the bit is set, with
    the polygon offset in the shader text, since D3D11's `DepthBias` does not apply to a written depth.
    Found with the backend's pixel probe (`RECOMP_D3D11_PX`). `RECOMP_D3D11_W_DEPTH=0` turns it off. Only the
    combiner path writes it; XDK titles always program the combiners.
18. **Render scale with 2D blits** (`RECOMP_RENDER_SCALE`, needs `-DXBOXRECOMP_ENHANCE=ON`). GPU blits, blits
    into a render target and the write-back only took unscaled surfaces: at 2x, GET READY, the pause and the
    carousel had no background. They now copy the region times the factor, and the write-back takes one texel
    of each n x n. Checked at 2x, 3x and 4x, 60 FPS in a match. With `display.aspect` 16:9 they also take
    padded (hor+) surfaces.
19. **Shader cache** (`compile`): compiled HLSL is kept in `shadercache\` (hash of target and source). On a
    test route, 42 slow compiles (520 ms, the worst 64 ms) cold, none warm. `RECOMP_SHADER_CACHE=<dir>|0`.
20. **Low latency** (swap chain): `SetMaximumFrameLatency(1)` and, with VSync off, `ALLOW_TEARING` on the swap
    chain and `Present` (falls back when unsupported). `RECOMP_D3D11_LOW_LATENCY=0`.
21. **Field presentation** (with the progressive patch off, `RECOMP_KFC_PROGRESSIVE=0`): a 640x240 field is
    stretched to 4:3 in any window, with an adaptive or blend deinterlacer (`RECOMP_FIELD_DEINTERLACE`).

## USB

22. **Rumble** (`usb_gamepad_out`, `ohci.c`): rumble reports (interrupt OUT, and `SET_REPORT` 21 09 on the
    control pipe) were dropped; they now go to `xbox_InputSetState`. Not yet seen from Kung Fu Chaos in a test
    run. `RECOMP_RUMBLE=0`.

## Game patch

23. **True progressive matches (480 lines).** The game only has 480i: matches render as 640x240 fields, which
    on a PC screen bob or comb. Neither xemu nor Cxbx-Reloaded handles it; the only "force 480p" known is a
    modchip's (XboxHD+, undocumented). See `patches/README.md`. Checked: match, HUD, fog, pause, back out with
    B and reload, quit to menu, character select, 60 FPS.

## Checked

Unattended runs (a pad script through `RECOMP_PAD_LIVE`): Battle Game (free for all, 3 CPU players, 4 HUDs),
Championship (12 rounds), Miniseries, Freestyle, four players joining with Start and fighting, backing out
of a load with B and re-entering, pause, quit to menu. Saves and unlocks persist. Not yet checked:
Rehearsal, Special Features, 2 to 4 physical controllers. Known: faint vertical lines in the pause's blurred
background (x ~195 and ~505 of 640); with 16:9 the menu backgrounds are stretched at the sides and the
pause's sides are black.
