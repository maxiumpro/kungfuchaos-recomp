"""Applies the Kung Fu Chaos patches to the generated C (src/recomp/gen).

regen.sh runs it right after the recompiler. Each function is found by name in any
recomp_*.c (a regeneration can move it to another file), only its body is changed, and the
script stops if the original code is not what it expects: a lifter change never leaves a
half-applied patch. A file that already has the patch is left alone.

Usage: python apply.py [gen directory] [--kick-wait] [--ohci-direct]
(the two flags only for the kfc-v2 toolkit; see patches/README.md)
"""
import glob, os, re, sys

_ARGS = [a for a in sys.argv[1:] if not a.startswith('--')]
GEN = _ARGS[0] if _ARGS else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'recomp', 'gen')

HELPER = '''/* KFC (local patch, patches/): true progressive matches. sub_000C6E30 sets
 * a match up as 640x240 fields: D3DDevice_Reset with BackBufferHeight 240,
 * D3DPRESENTFLAG_FIELD (0x80) and the game's own 640x240 surface headers;
 * sub_000C7070 then offsets every other field by -0.5 line. Progressive: 480
 * lines, no FIELD flag, the headers' height 480 (their memory already holds
 * 640x480) and no field offset. MEM8(0x3821BC) means "in a match" and stays.
 * On by default; RECOMP_KFC_PROGRESSIVE=0: the console's fields. */
static int kfc_progressive(void)
{
    static int on = -1;
    if (on < 0) { const char *e = getenv("RECOMP_KFC_PROGRESSIVE"); on = !(e && *e == '0'); }
    return on;
}

'''

HEADERS = '''    if (kfc_progressive()) {
        /* KFC force 480p: the match hands D3DDevice_Reset its own surface
         * headers (PP.BufferSurfaces[0..1], PP.DepthStencilSurface): the two
         * display buffers and the depth buffer, set up as 640x240 fields.
         * Their memory holds 640x480 (1200 KB each, 0x588000 / 0x6B4000 /
         * 0x7E0000), so only the height in each header's size word changes. */
        static const uint32_t offs[3] = {0xE8, 0x100, 0x118};
        int q;
        for (q = 0; q < 3; q++) {
            uint32_t d = esi + offs[q], sz = MEM32(d + 0x10);
            if (((sz >> 12) & 0xFFF) == 239)
                MEM32(d + 0x10) = (sz & ~0x00FFF000u) | (479u << 12);
        }
    }
'''

# (function, [(original, patched)]): each original must appear exactly once in the body.
PATCHES = [
    ('sub_000C6E30', [
        ('    MEM32(esi + 0x24) = 0x120;\n',
         '    MEM32(esi + 0x24) = kfc_progressive() ? 0x240 : 0x120;  /* KFC: force 576p (PAL) */\n'),
        ('    MEM32(esi + 0x24) = 0xF0;\n',
         '    MEM32(esi + 0x24) = kfc_progressive() ? 0x1E0 : 0xF0;   /* KFC: force 480p */\n'),
        ('    edx = edx | 0x80;\n',
         '    if (!kfc_progressive()) edx = edx | 0x80;   /* KFC: D3DPRESENTFLAG_FIELD only without force 480p */\n'),
        ('    MEM8(0x3821BC) = 1;\n',
         '    MEM8(0x3821BC) = 1;   /* KFC: "in a match" (not "fields"): kept, or the HUD is not drawn */\n'),
        ('    PUSH32(esp, 0x000C6ED8u); RECOMP_ABI_CALL(0x002B9590u, sub_002B9590);',
         HEADERS + '    PUSH32(esp, 0x000C6ED8u); RECOMP_ABI_CALL(0x002B9590u, sub_002B9590);'),
    ]),
    ('sub_000C7070', [
        ('    MEM32(esp + 4) = 0xBF000000u;\n',
         '    MEM32(esp + 4) = kfc_progressive() ? 0 : 0xBF000000u;   /* KFC: the odd field\'s -0.5 line, none in 480p */\n'),
    ]),
    # The other two readers of the field parity (device + 0x1990): with fields, the odd field uses a
    # different resource (+0x3C / +0xC) than the even one (+0x40 / +0x10). In 480p that moved the HUD
    # by about a quarter of a pixel every other frame. Progressive: always the no-fields branch, the
    # console's own without FIELD.
    ('sub_0002A0F0', [
        ('loc_0002A3A9: ;\n',
         'loc_0002A3A9: ;\n    if (kfc_progressive()) goto loc_0002A3B6;   /* KFC: no per-field resource in 480p */\n'),
    ]),
    ('sub_0002CB00', [
        ('loc_0002CB2D: ;\n',
         'loc_0002CB2D: ;\n    if (kfc_progressive()) goto loc_0002CB40;   /* KFC: no per-field resource in 480p */\n'),
    ]),
]


# memcpy (sub_00208EA0, MSVC's CRT one): with fewer than 4 bytes it jumps through the TrailUpVec table
# (0x208FEC) with `jmp [ecx*4 + 0x208FFC]` after `sub ecx, 4`. The lifter left that jump as
# RECOMP_ITAIL, and the 1-byte entry (0x00209004) is a label inside this function, not a function:
# the dispatcher does not find it, the jump is skipped and the byte is not copied (log "[ICALL] Failed
# to resolve VA 0x00209004", thousands per match). Seen in the cymbal stage: the floor is missing.
MEMCPY_OLD = '    g_seh_ebp = ebp; RECOMP_ITAIL(MEM32(ecx * 4 + 0x208FFC)); return; /* indirect tail jmp */\n'
MEMCPY_NEW = ('    { uint32_t _jt = MEM32(ecx * 4 + 0x208FFC); /* KFC patch: TrailUpVec, 0 and 1 byte are local */\n'
              '    if (_jt == 0x00208FFCu) goto loc_00208FFC;\n'
              '    if (_jt == 0x00209004u) goto loc_00209004;\n'
              '    g_seh_ebp = ebp; RECOMP_ITAIL(_jt); return; }\n')


def patch_memcpy():
    p = find_file('sub_00208EA0')
    raw = open(p, 'rb').read()
    crlf = b'\r\n' in raw
    s = raw.decode('utf-8').replace('\r\n', '\n')
    if 'TrailUpVec, 0 and 1 byte are local' in s:
        print('already patched (memcpy):', os.path.basename(p))
        return
    a, b = body(s, 'sub_00208EA0')
    t = s[a:b]
    if t.count(MEMCPY_OLD) != 1:
        sys.exit('apply.py: sub_00208EA0: the TrailUpVec jump was not found')
    s = s[:a] + t.replace(MEMCPY_OLD, MEMCPY_NEW, 1) + s[b:]
    if crlf:
        s = s.replace('\n', '\r\n')
    open(p, 'wb').write(s.encode('utf-8'))
    print('patched (memcpy):', os.path.basename(p))


# KickOff (sub_002BD8A0): sets the flush bit (0x10000 at NV2A 0x100410) and spins at loc_002BD8C0 until
# the walker clears it; its two callers (sub_002BD6F0, sub_002BD7A0) then write PUT (USER+0x40).
# Only with --kick-wait and only for the v0.15 toolkit (the kfc-v2 branch), which has xbox_SpinWaitKick,
# xbox_Nv2aKickPoke and g_xbox_kick_armed. With RECOMP_DEBUG=kick_event=1 the walker sleeps between
# KickOffs instead of polling every ~50 us, and the game has to wake it:
#  - the flush spin: RECOMP_SPIN_WAIT_KICK, what tools.recomp --spin-waits does with "sleep": "kick_event";
#  - every PUT store: if the walker is asleep, a nudge. The walker only watches PUT ~100 us after an ack
#    from its fast loop; after an ack in the middle of a pass it does not, and without the nudge that
#    store waited for the 1 ms tick (3 in a row and the walker gave up: "kicks in a row were found by
#    the 1 ms tick").
# The macros live here because the recomp_types.h of this generated code predates them.
KICK_EDITS = {
    'sub_002BD8A0': ('    if (CMP_NE(_fa, _fb)) { RECOMP_BACK_EDGE(0x002BD8CAu); goto loc_002BD8C0; } /* jne: not equal / not zero */\n',
                     '    if (CMP_NE(_fa, _fb)) { RECOMP_SPIN_WAIT_KICK(0x002BD8C0u); RECOMP_BACK_EDGE(0x002BD8CAu); goto loc_002BD8C0; }'
                     ' /* jne; KFC patch: KickOff flush wait */\n'),
    'sub_002BD6F0': ('    MEM32(eax + 0x40) = esi;\n',
                     '    MEM32(eax + 0x40) = esi;\n    RECOMP_KICK_POKE(); /* KFC patch: PUT store */\n'),
    'sub_002BD7A0': ('    MEM32(eax + 0x40) = edx;\n',
                     '    MEM32(eax + 0x40) = edx;\n    RECOMP_KICK_POKE(); /* KFC patch: PUT store */\n'),
}
KICK_MACRO = """#ifndef RECOMP_SPIN_WAIT_KICK   /* KFC patch (gen-patches/apply.py --kick-wait): templates/runtime/recomp_types.h */
extern volatile int g_xbox_spin_sleep, g_xbox_irq_pending, g_xbox_guest_cpu_waiters, g_xbox_kick_armed;
void xbox_SpinWaitKick(uint32_t va);
#define RECOMP_SPIN_WAIT_KICK(va) \\
    do { __atomic_thread_fence(__ATOMIC_SEQ_CST); if (g_xbox_spin_sleep | g_xbox_irq_pending | g_xbox_guest_cpu_waiters | g_xbox_kick_armed) xbox_SpinWaitKick(va); } while (0)
#endif
#ifndef RECOMP_KICK_POKE   /* KFC patch: a PUT store wakes a sleeping walker (the guest half of nv2a_kick_wake.h) */
void xbox_Nv2aKickPoke(void);
#define RECOMP_KICK_POKE() \\
    do { __atomic_thread_fence(__ATOMIC_SEQ_CST); if (g_xbox_kick_armed) xbox_Nv2aKickPoke(); } while (0)
#endif

"""


def patch_kickoff():
    p = find_file('sub_002BD8A0')
    raw = open(p, 'rb').read()
    crlf = b'\r\n' in raw
    s = raw.decode('utf-8').replace('\r\n', '\n')
    # An earlier macro block (it only had RECOMP_SPIN_WAIT_KICK) is removed and put back complete.
    i = s.find('#ifndef RECOMP_SPIN_WAIT_KICK')
    if i >= 0:
        j = s.find('\n\n', s.find('#endif', i))
        if 'RECOMP_KICK_POKE' not in s[i:j]:
            s = s[:i] + s[j + 2:]
    for fn, (old, new) in KICK_EDITS.items():
        r = body(s, fn)
        if r is None:
            sys.exit('apply.py: %s is not in %s (the three KickOff functions go together)' % (fn, os.path.basename(p)))
        a, b = r
        t = s[a:b]
        if new in t:
            continue
        if t.count(old) != 1:
            sys.exit('apply.py: in %s, not found (or found more than once): %r' % (fn, old.strip()))
        s = s[:a] + t.replace(old, new, 1) + s[b:]
    if '#define RECOMP_KICK_POKE()' not in s:
        a = min(body(s, fn)[0] for fn in KICK_EDITS)
        k = s.rfind('\n/**', 0, a)   # before the first function's comment
        s = s[:k + 1] + KICK_MACRO + s[k + 1:]
    if crlf:
        s = s.replace('\n', '\r\n')
    open(p, 'wb').write(s.encode('utf-8'))
    print('patched (KickOff + PUT):', os.path.basename(p))


# OHCI without faults (--ohci-direct): the interrupt (sub_002D1840) and the DPC (sub_002D1F14) of the
# game's USB driver read and write the controller's registers (InterruptStatus/Enable/Disable,
# CommandStatus) with 32-bit movs through a base register. Each one faulted and the fault handler
# emulated it: on macOS a signal per access. Now they go through xbox_MmioRead/Write, which in the
# v0.15 toolkit diverts the OHCI window to the model (the same ohci_read/ohci_write). The macro checks
# the range on every access: a RAM address stays a plain access, so it does not depend on which
# register holds the base. Plain 32-bit movs only; no read-modify-write. In a toolkit without the
# diversion, xbox_MmioRead does the raw access and faults as before.
OHCI_FNS = {'sub_002D1840': 6, 'sub_002D1F14': 11}   # expected accesses; if they change, the patch fails
OHCI_OFFS = r'(?:8|0xC|0x10|0x14)'
OHCI_RD = re.compile(r'^(\s*)(e[a-d]x|e[sd]i) = MEM32\((e[a-d]x) \+ (%s)\);$' % OHCI_OFFS, re.M)
OHCI_WR = re.compile(r'^(\s*)MEM32\((e[a-d]x) \+ (%s)\) = ([^;]*);$' % OHCI_OFFS, re.M)
OHCI_MACRO = '''#ifndef KFC_IO_R32   /* KFC patch (gen-patches/apply.py --ohci-direct) */
#define KFC_IO_R32(a) ((uint32_t)(a) >= 0xFD000000u ? xbox_MmioRead((uint32_t)(a), 4) : MEM32(a))
#define KFC_IO_W32(a, v) do { uint32_t _io_a = (uint32_t)(a), _io_v = (uint32_t)(v); \\
    if (_io_a >= 0xFD000000u) xbox_MmioWrite(_io_a, _io_v, 4); else MEM32(_io_a) = _io_v; } while (0)
#endif

'''


def patch_ohci_direct():
    p = find_file('sub_002D1840')
    raw = open(p, 'rb').read()
    crlf = b'\r\n' in raw
    s = raw.decode('utf-8').replace('\r\n', '\n')
    for fn, want in OHCI_FNS.items():
        r = body(s, fn)
        if r is None:
            sys.exit('apply.py: %s is not in %s (the two OHCI functions go together)' % (fn, os.path.basename(p)))
        a, b = r
        t = s[a:b]
        if 'KFC_IO_' in t:
            continue
        n_rd = len(OHCI_RD.findall(t))
        n_wr = len([m for m in OHCI_WR.finditer(t) if 'MEM' not in m.group(4)])
        if n_rd + n_wr != want:
            sys.exit('apply.py: in %s expected %d OHCI accesses, found %d reads + %d writes'
                     % (fn, want, n_rd, n_wr))
        t = OHCI_RD.sub(r'\1\2 = KFC_IO_R32(\3 + \4); /* KFC patch: OHCI */', t)
        t = OHCI_WR.sub(lambda m: m.group(0) if 'MEM' in m.group(4) else
                        '%sKFC_IO_W32(%s + %s, %s); /* KFC patch: OHCI */' % m.group(1, 2, 3, 4), t)
        s = s[:a] + t + s[b:]
    if '#ifndef KFC_IO_R32' not in s:
        a = min(body(s, fn)[0] for fn in OHCI_FNS)
        k = s.rfind('\n/**', 0, a)
        s = s[:k + 1] + OHCI_MACRO + s[k + 1:]
    if crlf:
        s = s.replace('\n', '\r\n')
    open(p, 'wb').write(s.encode('utf-8'))
    print('patched (direct OHCI):', os.path.basename(p))


def body(s, fn):
    """(start, end) of the body of `void fn(void)`; end = the next function, or the end of the file."""
    i = s.find('\nvoid %s(void)\n' % fn)
    if i < 0:
        return None
    j = s.find('\nvoid sub_', i + 1)
    return i + 1, (j + 1 if j >= 0 else len(s))


def find_file(fn):
    for p in sorted(glob.glob(os.path.join(GEN, 'recomp_*.c'))):
        with open(p, 'rb') as f:
            if ('\nvoid %s(void)' % fn).encode() in f.read():
                return p
    sys.exit('apply.py: %s not found in %s' % (fn, GEN))


def state(t, edits):
    """'patched' when every patched text is in body t, 'unpatched' when none is and every
    original is there exactly once, else 'inconsistent'. (A patched text can contain its
    original, so the originals alone do not tell.)"""
    if all(new in t for _, new in edits):
        return 'patched'
    if all(new not in t and t.count(old) == 1 for old, new in edits):
        return 'unpatched'
    return 'inconsistent'


def main():
    files = {}
    for fn, _ in PATCHES:
        files.setdefault(find_file(fn), []).append(fn)
    out = {}   # path -> (crlf, new text); nothing is written until every file checks out
    for p, fns in files.items():
        raw = open(p, 'rb').read()
        crlf = b'\r\n' in raw
        s = raw.decode('utf-8').replace('\r\n', '\n')
        states = {}
        for fn, edits in PATCHES:
            if fn in fns:
                a, b = body(s, fn)
                states[fn] = state(s[a:b], edits)
        helper = HELPER in s
        if all(v == 'patched' for v in states.values()) and helper:
            print('already patched:', os.path.basename(p))
            continue
        bad = [fn for fn, v in states.items() if v != 'unpatched']
        if bad or helper:
            sys.exit('apply.py: %s is partly patched or not what this script expects (%s); '
                     'regenerate it with regen.sh' % (os.path.basename(p), ', '.join(bad) or 'helper'))
        for fn, edits in PATCHES:
            if fn not in fns:
                continue
            a, b = body(s, fn)
            t = s[a:b]
            for old, new in edits:
                t = t.replace(old, new, 1)
            s = s[:a] + t + s[b:]
        # The helper goes before the first patched function in this file (each file gets its own copy).
        a = min(body(s, fn)[0] for fn in fns)
        k = s.rfind('\n/**', 0, a)   # the function's header comment
        s = s[:k + 1] + HELPER + s[k + 1:]
        s = s.replace('#include "recomp_funcs.h"\n', '#include "recomp_funcs.h"\n#include <stdlib.h>   /* KFC patch */\n', 1)
        out[p] = (crlf, s, fns)
    for p, (crlf, s, fns) in out.items():
        if crlf:
            s = s.replace('\n', '\r\n')
        open(p, 'wb').write(s.encode('utf-8'))
        print('patched:', os.path.basename(p), ', '.join(fns))


main()
patch_memcpy()
if '--kick-wait' in sys.argv:
    patch_kickoff()
if '--ohci-direct' in sys.argv:
    patch_ohci_direct()
