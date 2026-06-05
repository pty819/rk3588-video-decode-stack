# Verifier scripts

> The .sh scripts used to prove the build is real. Each one
> is short, has a single purpose, and exits 0 only when
> the corresponding subsystem is actually working.

## verify-detlev-ffmpeg-build.sh

End-to-end smoke test for the Collabora detlev/ffmpeg build.
Runs 5 checks:

1. `ldd` shows `libavcodec.so.62` (in-tree .so, not apt's
   `.60`).
2. `ffmpeg -hwaccels` shows `v4l2request`.
3. `ffmpeg -decoders` shows the 6 v4l2m2m codec wrappers
   (h264_v4l2m2m, hevc_v4l2m2m, vp8_v4l2m2m, vp9_v4l2m2m,
   av1_v4l2m2m, mpeg2_v4l2m2m).
4. A 4K HEVC test clip decodes via rkvdec (the
   `Using V4L2 media driver rkvdec (7.0.11) for S265` line),
   and the decode speed is `>= 1.0x`.
5. (If `/usr/local/bin/ffmpeg` exists) Post-install sanity:
   - `which ffmpeg` returns `/usr/local/bin/ffmpeg`
   - `ffmpeg -version` reports the `dfa10f6` HEAD
   - `libavcodec.so.62` is in `/usr/local/lib/...`
   - `libavcodec.so.60` is untouched in `/usr/lib/...`
   - The apt ffmpeg packages are on `apt-mark hold`
   - A real 4K HEVC decode through the installed binary
     uses rkvdec (no `LD_LIBRARY_PATH`).

```bash
bash scripts/verify-detlev-ffmpeg-build.sh
```

**Source:** see `scripts/verify-detlev-ffmpeg-build.sh` in
this repository.

## The 5 checks, in detail

### Check 1: in-tree .so binding

```bash
LDCODEC=$(LD_LIBRARY_PATH="$LDP" ldd "$SRC/ffmpeg" \
  | grep libavcodec | awk '{print $3}' | head -1)
```

This catches the classic "I rebuilt ffmpeg but the old
.so is still in the link path" error. If the in-tree
`.so` isn't `libavcodec.so.62.11.100`, the build is broken.

### Check 2: v4l2request hwaccel

```bash
HWACCELS=$(LD_LIBRARY_PATH="$LDP" "$SRC/ffmpeg" \
  -hide_banner -hwaccels 2>/dev/null)
echo "$HWACCELS" | grep -qE "^v4l2request"
```

The v4l2request hwaccel is the *only* way to use the
stateless path. The Collabora fork does **not** introduce
new decoder names like `hevc_v4l2request`; it adds a
hwaccel layer on top of `hevc_v4l2m2m`. This check
verifies that layer is compiled in.

A common false-FAIL: grepping for `_(v4l2request)$` in
`-decoders`. There's no such entry. Use `-hwaccels`.

### Check 3: 6 v4l2m2m decoders

```bash
M2M_COUNT=$(LD_LIBRARY_PATH="$LDP" "$SRC/ffmpeg" \
  -hide_banner -decoders 2>/dev/null \
  | grep -cE "_(v4l2m2m) +V4L2")
```

The v4l2request hwaccel rides on the v4l2m2m decoders.
If they're missing, the hwaccel won't be able to do
anything. We expect 9: h264_v4l2m2m, hevc_v4l2m2m,
mpeg1_v4l2m2m, mpeg2_v4l2m2m, mpeg4_v4l2m2m, vc1_v4l2m2m,
vp8_v4l2m2m, vp9_v4l2m2m, plus h263_v4l2m2m.

### Check 4: real 4K HEVC decode

```bash
LD_LIBRARY_PATH="$LDP" "$SRC/ffmpeg" -v info \
  -hwaccel v4l2request -hwaccel_output_format drm_prime \
  -i "$TESTCLIP" -f null - 2>"$LOG" 1>/dev/null

grep -q "Using V4L2 media driver rkvdec.*for S265" "$LOG"
```

This is the canonical "real hardware decode" check. The
S265 line proves the kernel's rkvdec matched the HEVC
input and the rkvdec2 driver is doing the work.

The speed check (`speed >= 1.0x`) is a sanity check —
software HEVC on RK3588S tops out at 0.3-0.5x.

### Check 5: post-install

This is the only check that requires the install to have
happened. If `/usr/local/bin/ffmpeg` doesn't exist, check 5
is skipped. The checks within:

- `which ffmpeg` → `/usr/local/bin/ffmpeg` (PATH
  priority over `/usr/bin/`)
- `ffmpeg -version` → `dfa10f6` (the Collabora HEAD)
- `libavcodec.so.62` in `/usr/local/lib/...` (the install
  actually happened)
- `libavcodec.so.60` in `/usr/lib/...` (the apt install
  is untouched)
- `apt-mark showhold` returns the 8 held packages
  (the `apt-mark hold` was run)
- A 4K HEVC decode through `/usr/local/bin/ffmpeg`
  matches rkvdec (proves the installed binary actually
  works, no LD_LIBRARY_PATH shenanigans)

## Other scripts in the repo

`verify-cmake-build.sh` — generic CMake build verification
(disk space, gcc version, etc.). Not specific to this stack.

`verify-vaapi-stack.sh` — verifies the woodyst/rockchip-vaapi
bridge for the older stateful m2m path. Not used in this
stack, but kept for reference.

`verify-v4l2-m2m.sh` — verifies the v4l2 m2m device
existence and capability. Should be run as a pre-flight
check before the ffmpeg build.

`verify-mpv-v4l2m2m-copy.sh` — verifies that the apt mpv
0.37 with `--hwdec=v4l2m2m-copy` actually works. (Spoiler:
it doesn't, on 7.0+ mainline. The script documents the
failure mode.)

`verify-gstreamer-v4l2sl.sh` — verifies the gstreamer
v4l2sl elements can decode a 4K HEVC clip end-to-end.

## Running all checks

```bash
# Pre-flight
bash scripts/verify-v4l2-m2m.sh
bash scripts/verify-vaapi-stack.sh  # optional, for legacy path

# Post-build
bash scripts/verify-detlev-ffmpeg-build.sh

# Post-install (re-run for sanity)
bash scripts/verify-detlev-ffmpeg-build.sh

# Cross-validation
bash scripts/verify-gstreamer-v4l2sl.sh
```

A successful end-to-end run is when the ffmpeg and
gstreamer scripts both pass, the v4l2 m2m device is
present, and the post-install check shows `/usr/local/bin/ffmpeg`
as the active ffmpeg.
