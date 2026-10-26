"""Applies the Kung Fu Chaos patches to the generated C (src/recomp/gen).

regen.sh runs it right after the recompiler. Each function is found by name in any
recomp_*.c (a regeneration can move it to another file), only its body is changed, and the
script stops if the original code is not what it expects: a lifter change never leaves a
half-applied patch. A file that already has the patch is left alone.

Usage: python apply.py [gen directory]
"""
import glob, os, sys

GEN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
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
]


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


def main():
    files = {}
    for fn, _ in PATCHES:
        files.setdefault(find_file(fn), []).append(fn)
    p0 = find_file('sub_000C6E30')
    for p, fns in files.items():
        raw = open(p, 'rb').read()
        crlf = b'\r\n' in raw
        s = raw.decode('utf-8').replace('\r\n', '\n')
        if 'kfc_progressive' in s:
            print('already patched:', os.path.basename(p))
            continue
        for fn, edits in PATCHES:
            if fn not in fns:
                continue
            a, b = body(s, fn)
            t = s[a:b]
            for old, new in edits:
                if t.count(old) != 1:
                    sys.exit('apply.py: in %s, not found (or found more than once): %r' % (fn, old.strip()))
                t = t.replace(old, new, 1)
            s = s[:a] + t + s[b:]
        if p == p0:
            # The helper goes before its first user, which also covers sub_000C7070 in the same file.
            a, _ = body(s, 'sub_000C6E30')
            k = s.rfind('\n/**', 0, a)   # the function's header comment
            s = s[:k + 1] + HELPER + s[k + 1:]
            s = s.replace('#include "recomp_funcs.h"\n', '#include "recomp_funcs.h"\n#include <stdlib.h>   /* KFC patch */\n', 1)
        else:
            # sub_000C7070 is in another file: it needs its own copy of the helper.
            a, _ = body(s, 'sub_000C7070')
            k = s.rfind('\n/**', 0, a)
            s = s[:k + 1] + HELPER + s[k + 1:]
            s = s.replace('#include "recomp_funcs.h"\n', '#include "recomp_funcs.h"\n#include <stdlib.h>   /* KFC patch */\n', 1)
        if crlf:
            s = s.replace('\n', '\r\n')
        open(p, 'wb').write(s.encode('utf-8'))
        print('patched:', os.path.basename(p), ', '.join(fns))


main()
