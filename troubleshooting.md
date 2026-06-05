# Troubleshooting

> What we got wrong, and the fixes. The "5 minute fixes" that
> turned into multi-hour rabbit holes.

## `error: 'PL_ALPHA_NONE' undeclared`

The build dies at `libavfilter/vf_libplacebo.c:940:44`.

**Diagnosis:**

```bash
$ pkg-config --cflags libplacebo
-I/usr/include/libplacebo
$ grep -rE "PL_ALPHA_(NONE|UNKNOWN)" /usr/include/libplacebo/*.h
/usr/include/libplacebo/colorspace.h:    PL_ALPHA_UNKNOWN = 0,
/usr/include/libplacebo/colorspace.h:    PL_ALPHA_STRAIGHT = 1,
/usr/include/libplacebo/colorspace.h:    PL_ALPHA_PREMULTIPLIED = 2,
# No PL_ALPHA_NONE.
```

**Cause:** libplacebo 7.x renamed the `PL_ALPHA_NONE` enum
value to `PL_ALPHA_UNKNOWN`. The Collabora detlev/ffmpeg
fork was written against libplacebo 6.x, so the build
expects `PL_ALPHA_NONE`. The compiler's
"did you mean `PL_LOG_NONE`?" suggestion is misleading —
that's a different macro for log levels.

**Fix:** see [`libplacebo-api-drift`](libplacebo-api-drift)
for the full discussion. The one-liner:

```bash
sed -i 's/PL_ALPHA_NONE/PL_ALPHA_UNKNOWN/' \
  libavfilter/vf_libplacebo.c
```

After this, re-run `make` from the same source tree. The
patch is in `libavfilter/vf_libplacebo.c:940`; the fork's
own source uses the old name in exactly one place, so the
fix is local.

## `apt build-dep mpv` fails: "you must put deb-src URIs"

This is a common gotcha for cross-distro / cross-pocket
work. The armbian noble pocket doesn't enable `deb-src` by
default.

**Fix:** add `deb-src` URIs to `/etc/apt/sources.list` (or
the armbian-specific file under `/etc/apt/sources.list.d/`)
and re-run `apt update`. **Or** skip `apt build-dep mpv`
entirely and install the mpv build deps manually (see
[`install`](install) for the list).

**Long-term:** the `deb-src` question is unrelated to this
stack. We worked around it by listing the deps explicitly.

## mpv 0.41 doesn't have v4l2request

Symptom: `mpv --hwdec=v4l2request 4k-hevc.mkv` shows
`[vd] Selected decoder: hevc - HEVC (High Efficiency Video
Coding)` (soft decode).

**Diagnosis:**

```bash
$ grep -nE "v4l2|\"vaapi|\"drmprime" video/decode/vd_lavc.c | head -10
video/decode/vd_lavc.c:273:    {"vaapi",           HWDEC_FLAG_AUTO | HWDEC_FLAG_WHITELIST},
video/decode/vd_lavc.c:277:    {"videotoolbox",    HWDEC_FLAG_AUTO | HWDEC_FLAG_WHITELIST},
video/decode/vd_lavc.c:282:    {"vaapi-copy",      HWDEC_FLAG_AUTO | HWDEC_FLAG_WHITELIST},
video/decode/vd_lavc.c:286:    {"videotoolbox-copy", HWDEC_FLAG_AUTO | HWDEC_FLAG_WHITELIST},
```

**Cause:** Upstream mpv 0.41 removed v4l2request. PR
#14690 and #16282 are still open. The fork `~ft/mpv` has
the code, but only against mpv 0.40 + ffmpeg 7.x.

**Fix:** see [`mpv-rejected`](mpv-rejected). The short
answer: don't use mpv. Use `ffplay` or gstreamer.

## `apt install vlc` doesn't work for 4K HEVC

Symptom: `vlc 4k-hevc.mkv` runs but the CPU is at 100%
and the playback is choppy.

**Diagnosis:** `vlc --list-modules | grep v4l2` shows
`libv4l2_plugin.so` (input device) but no
`avcodec-plugin`'s v4l2-request decoder. The noble apt
package was built without `--enable-v4l2-request`.

**Fix:** see [`vlc-rejected`](vlc-rejected). The short
answer: don't use VLC. Use `ffplay` or gstreamer.

## `speed=0.3x` despite `v4l2request` hwaccel

Symptom: ffmpeg is using `hevc_v4l2request` but only at
0.3-0.5x real-time, which is software decode speed on
RK3588S.

**Diagnosis:**

1. Is the `S265` line present in the log?
2. If yes, is the CMA at least 512M?
3. If yes, is `/dev/dri/renderD128` accessible?

```bash
# Check 1: kernel log
dmesg | grep -E "rkvdec|v4l2" | tail -10

# Check 2: CMA
grep CmaTotal /proc/meminfo

# Check 3: DRM
ls -la /dev/dri/
```

**Cause:** most likely the CMA size is too small. The
default 128M is enough for 1080p but not for 4K. The
4K HEVC decode may fall back to internal software paths
when the kernel can't allocate reference frames.

**Fix:** set `extraargs=cma=512M` in
`/boot/armbianEnv.txt` and reboot.

## `ffmpeg: symbol lookup error` after a parallel install

Symptom: a system command (mpv, vlc, anything) crashes
with `symbol lookup error: /usr/local/lib/...`.

**Diagnosis:** `LD_LIBRARY_PATH` is pointing to
`/usr/local/lib/...` but the binary was linked against
apt's `.60` ABI.

**Fix:**

```bash
# Don't set LD_LIBRARY_PATH globally. The /usr/local/lib
# path is already in ldconfig's search order.
unset LD_LIBRARY_PATH
sudo ldconfig

# Verify
ldd $(which ffmpeg) | grep libavcodec
# → libavcodec.so.62 => /usr/local/lib/aarch64-linux-gnu/libavcodec.so.62
```

## `Using software decoding` in `ffmpeg -v info`

Symptom: ffmpeg log shows `[vd] Using software decoding`
instead of `Using V4L2 media driver rkvdec ... S265`.

**Diagnosis:** the `-hwaccel` flag isn't reaching the
decoder.

**Common causes:**

1. **Wrong hwaccel name.** In the Collabora fork, it's
   `v4l2request`, not `v4l2-request` and not `rkmpp` and
   not `v4l2-_request`.
2. **Missing `-hwaccel_output_format drm_prime`** —
   some ffmpeg builds require this to actually invoke the
   hwaccel.
3. **Stream doesn't need hwaccel** — for a 480p test
   pattern, ffmpeg may decide software decode is fast
   enough and skip the hwaccel.

**Fix:**

```bash
ffmpeg -v info \
  -hwaccel v4l2request \
  -hwaccel_output_format drm_prime \
  -i /path/to/4k-hevc.mkv \
  -f null - 2>&1 | grep -E "hwaccel|driver|Stream mapping"
```

If the log shows `Stream #0:0 -> #0:0 (hevc (native) ->
wrapped_avframe (native))`, you're on the right path.

## HEVC BluRay rip shows green bars / dropped frames

Symptom: real 4K HEVC BluRay content (B-frames, complex
RPS) shows corruption or dropped frames; synthetic test
content is fine.

**Diagnosis:** the HEVC ST RPS wip bug. See
[`known-bugs`](known-bugs) for the full discussion.

**Fix options:**

1. **Switch to LibreELEC jernejsk ffmpeg 7.1** + ~ft/mpv
   mpv 0.40. Kodi / LibreELEC production stack. Loses
   the ext-SPS-RPS improvements in 8.0.1.
2. **Wait for Collabora to land the fix.** Track the
   `wip: fix st rps` commit. No ETA.
3. **Use gstreamer** with `v4l2slh265dec` — gstreamer's
   RPS handling is independent of ffmpeg's.

For non-BluRay content (test patterns, video podcasts,
game captures), this bug doesn't trigger.

## `apt-mark hold` rejected by `apt upgrade`

Symptom: `apt upgrade` claims to upgrade `ffmpeg` despite
the hold.

**Diagnosis:** the hold only works on the exact version
listed in `dpkg -l`. If a new patch version is available
(6.1.5 instead of 6.1.1), the hold is effective but
`apt` may still warn.

**Fix:** confirm the hold is in place:

```bash
apt-mark showhold | grep ffmpeg
# → ffmpeg
# → libavcodec60
# → ...
```

If the package is being upgraded despite the hold,
check `dpkg --audit` for inconsistencies.
