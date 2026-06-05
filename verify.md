# Verify

> Prove the build is real. A "looks fine, ship it" answer is
> not verification. Every check below produces a concrete
> artifact: a string match, a speed number, or a kernel log
> line.

## The single most important check

```bash
ffmpeg -v info -hwaccel v4l2request -hwaccel_output_format drm_prime \
  -i /tmp/vtest/test_4k_hevc.mp4 -f null -
```

You must see all three of:

1. **`[AVHWFramesContext @ ...] Using V4L2 media driver rkvdec (7.0.11) for S265`**
   This line is the canonical "real hardware decode" proof.
2. **`Stream #0:0 -> #0:0 (hevc (native) -> wrapped_avframe (native))`**
   The Stream mapping must show `wrapped_avframe` as the
   output, not `rawvideo` (which would be a software decode
   landing in memory).
3. **`speed=N.NNx` where `N >= 1.0`.** A 4K HEVC test clip
   with libx265 should run at 4-5x real-time on RK3588S. If
   you see `speed=0.3x` to `0.5x`, you're in soft decode and
   the CPU is doing the work.

If any of the three is missing, the build is broken. Do not
trust the absence of error messages.

## A 4K HEVC test clip

If you don't have a real 4K HEVC clip, generate one with
`ffmpeg` itself (uses the system libx265):

```bash
mkdir -p /tmp/vtest
/usr/local/bin/ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "testsrc2=size=3840x2160:rate=30:duration=3" \
  -c:v libx265 -preset ultrafast -pix_fmt yuv420p \
  /tmp/vtest/test_4k_hevc.mp4
```

This takes about 15-20 seconds with `ultrafast`. The
generated file is 3-4 MB. It's a synthetic test pattern, not
real content, but the decode path is the same.

## The full verify script

For a comprehensive check that exercises the build, the ABI,
the hwaccels, and a real decode, run:

```bash
bash scripts/verify-detlev-ffmpeg-build.sh
```

This script (in [`verify-scripts/`](verify-scripts/index))
runs 5 checks:

1. `ldd` shows `libavcodec.so.62` (not `.60`) — proves the
   in-tree .so is being used.
2. `ffmpeg -hwaccels` lists `v4l2request` — proves the
   hwaccel is compiled in.
3. `ffmpeg -decoders` shows the 6 v4l2m2m codec wrappers
   that the v4l2request hwaccel rides on.
4. The 4K HEVC decode produces the `rkvdec ... S265` line
   and a `speed >= 1.0x`.
5. **Post-install** (if `/usr/local/bin/ffmpeg` exists):
   - `which ffmpeg` returns `/usr/local/bin/ffmpeg`
   - `ffmpeg -version` reports the `dfa10f6` HEAD
   - `libavcodec.so.62` is in `/usr/local/lib/...`
   - `libavcodec.so.60` is untouched in `/usr/lib/...`
   - The 6+ apt ffmpeg packages are on `apt-mark hold`
   - A real 4K HEVC decode through the installed binary
     uses rkvdec (no `LD_LIBRARY_PATH` needed).

The script exits 0 only if all 5 checks pass. Run it after
every `make` to confirm the build is real.

## What "speed=4.67x" actually means

For our 3-second, 30-fps test clip, `speed=4.67x` means
ffmpeg decoded the 90 frames in 0.64 seconds of wall time.
The kernel's rkvdec completed each frame in roughly
`(1/30) / 4.67 = 7.1 ms`. That's a real hardware decode;
software HEVC on RK3588S tops out at 0.3-0.5x.

A specific test clip's speed depends on the content. A
noisy 4K BluRay rip with B-frames and complex RPS may run
slower (2-3x) due to the kernel-side work. A simple
test pattern is fastest.

## Common false-positives

The verify script can pass on a build that's *almost*
working but not quite. Watch for:

- **Speed 5x but no `S265` line.** This means the decoder
  was hw-accelerated but to a different driver (e.g.
  `rockchip-vpu-vp8-dec`). Unlikely, but possible if the
  kernel has more than one rkvdec registered. Check with
  `ls /dev/video*` to see what devices are present.
- **`S265` line present, speed 0.5x.** This is impossible
  unless the kernel is rejecting some frames and
  ffmpeg is falling back. Check `dmesg` after the decode
  for errors.
- **Verify script passes but `ffplay` of a real file
  shows stuttering.** Real content (not a test pattern)
  can stress paths that synthetic content doesn't.
  Specifically the HEVC ST RPS wip bug. See
  [`known-bugs`](known-bugs).

## What to do if a check fails

The verify script prints what it was looking for and what
it found. The fixes are in
[`troubleshooting`](troubleshooting).
