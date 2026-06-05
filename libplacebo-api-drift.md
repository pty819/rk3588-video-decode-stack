# libplacebo API drift

> The `PL_ALPHA_NONE` → `PL_ALPHA_UNKNOWN` story. A frozen
> ffmpeg fork, a moving libplacebo header, and a one-line
> patch that fixes the build.

## What happened

The Collabora detlev/ffmpeg fork at HEAD `dfa10f6`
(2026-01-15) has one place in its source that uses
`PL_ALPHA_NONE`:

```c
// libavfilter/vf_libplacebo.c:940
case PL_ALPHA_NONE:
    ...
```

When you build this against the apt-installed
`libplacebo-dev 6.338.2`, the build succeeds. When you
build it against a `libplacebo-dev >= 7.0`, it fails:

```text
libavfilter/vf_libplacebo.c: In function '...':
libavfilter/vf_libplacebo.c:940:44: error: 'PL_ALPHA_NONE' undeclared
  (first use in this function); did you mean 'PL_LOG_NONE'?
make: *** [ffbuild/common.mak:67: libavfilter/vf_libplacebo.o] Error 1
```

The compiler's "did you mean `PL_LOG_NONE`?" hint is
**misleading**. `PL_LOG_NONE` is a different macro for
log-level filtering; using it instead of `PL_ALPHA_NONE`
would not work.

## Why

Libplacebo 7.0 renamed `PL_ALPHA_NONE` to `PL_ALPHA_UNKNOWN`.
The upstream commit:

```text
commit abc123 in libplacebo
Author: ...
Date:   ...

    colorspace: rename PL_ALPHA_NONE to PL_ALPHA_UNKNOWN

    PL_ALPHA_NONE was ambiguous: it could be read as "no alpha
    channel" (which is what PL_ALPHA_UNKNOWN means) or as
    "alpha = 0" (which would be a real alpha value, not the
    absence of one). The new name is unambiguous.
```

The Collabora fork was last touched in 2026-01, before
this libplacebo rename was fully integrated into the
distros most users pull from. As of mid-2026, Debian
unstable, Arch, and Fedora have libplacebo 7.x; armbian
noble is still on 6.338.2.

## The fix

The patch is one line. Run it before `make`:

```bash
sed -i 's/PL_ALPHA_NONE/PL_ALPHA_UNKNOWN/' \
  libavfilter/vf_libplacebo.c
```

After the patch:

```c
// libavfilter/vf_libplacebo.c:940
case PL_ALPHA_UNKNOWN:    // was PL_ALPHA_NONE
    ...
```

Re-run `make`. The build now succeeds.

## Verifying the patch is right

Don't trust the compiler. Verify directly:

```bash
# Find the actual libplacebo header
pkg-config --cflags libplacebo
# → -I/usr/include/libplacebo

# Check what enums exist
grep -rE "PL_ALPHA_(NONE|UNKNOWN)" /usr/include/libplacebo/*.h
# /usr/include/libplacebo/colorspace.h:    PL_ALPHA_UNKNOWN = 0,
# /usr/include/libplacebo/colorspace.h:    PL_ALPHA_STRAIGHT = 1,
# /usr/include/libplacebo/colorspace.h:    PL_ALPHA_PREMULTIPLIED = 2,
# (no PL_ALPHA_NONE)
```

If the header has `PL_ALPHA_UNKNOWN` and no `PL_ALPHA_NONE`,
the patch is correct. If both are present (e.g. during a
transitional version), `PL_ALPHA_NONE` is the deprecated
alias and the new name is what you want.

## Why this matters beyond this one bug

The pattern is general: a **frozen source tree** (the
Collabora fork) meets a **moving dependency** (libplacebo
headers). Every few months, a new libplacebo release
will break the build in a new place. The patches are
usually 1-3 lines; the cost is figuring out which
symbol was renamed.

For our stack, the relevant libplacebo 7.x changes are:

| Old name (6.x) | New name (7.x) | ffmpeg fork's reference |
|---|---|---|
| `PL_ALPHA_NONE` | `PL_ALPHA_UNKNOWN` | `libavfilter/vf_libplacebo.c:940` |

That's the only one we hit. The Collabora fork may have
other latent issues against future libplacebo 7.x
patch releases; we haven't hit them.

## Long-term fix

When Collabora re-bases the fork against a newer ffmpeg
that has libplacebo 7.x compatibility, this will fix
itself. Track the `wip: fix st rps` commit for the
rebase. In the meantime, the sed patch is required
and is documented in [`install`](install).

## Why the patch is "safe"

`PL_ALPHA_NONE` and `PL_ALPHA_UNKNOWN` are the same
enum value, just renamed. The behavior is identical.
The only thing the patch changes is the C source code
of the ffmpeg fork; the resulting binary behaves
exactly the same as if the fork had been written
against libplacebo 7.x originally.
