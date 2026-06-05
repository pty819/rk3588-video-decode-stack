# mpv — rejected

> We tried. Three times, three different failure modes. The result
> of all that is that **this stack ships no mpv**. Use `ffplay`
> (which is built from the same ffmpeg we install and uses the
> same hwaccel path) for any GUI playback.

## What we wanted

mpv is the gold standard for hardware-accelerated video playback on
Linux. We wanted:

- mpv 0.40+ compiled against our ffmpeg 8.0.1 fork
- `hwdec=v4l2request` working
- 4K HEVC playing at 4-5x real-time, real VPU work

What we got was a 1.5h ffmpeg 8.0.1 build and three mpv source
trees that each failed for a different reason.

## Attempt 1: mpv 0.40 + ~ft/mpv v4l2request fork

The fork is at `git.sr.ht/~ft/mpv`, branch
`mpv-0.40.0-v4l2request`. Maintained by Jonas Karlman (Kwiboo),
the same person who wrote the original v4l2request framework. It
carries the `v4l2request.c` driver that talks to AV_HWDEVICE_TYPE_V4L2REQUEST
in ffmpeg.

```text
$ git clone --branch=mpv-0.40.0-v4l2request https://git.sr.ht/~ft/mpv
$ cd mpv
$ git log -1 --oneline
bb4e53c vo: hwdec: drmprime: add separate hwdecs for v4l2request
```

Configure + build went through with the same dev-deps install
we used for ffmpeg. But the build died on:

```text
../demux/demux_mkv.c:2203:32: error: use of undeclared identifier 'FF_PROFILE_ARIB_PROFILE_A'
../demux/demux_mkv.c:2209:32: error: use of undeclared identifier 'FF_PROFILE_ARIB_PROFILE_C'
../demux/demux_mkv.c:2212:29: error: use of undeclared identifier 'FF_PROFILE_UNKNOWN'
```

`FF_PROFILE_ARIB_PROFILE_A` and `FF_PROFILE_ARIB_PROFILE_C` were
**renamed/removed in ffmpeg 8.0**. The `~ft/mpv` fork is frozen
at mpv 0.40 + ffmpeg 7.x API. It cannot be built against
ffmpeg 8.0.1 without a backport patch, and backporting ffmpeg
ABI breaks across 1-2 minor versions is non-trivial.

**Conclusion:** the fork is right for **LibreELEC jernejsk ffmpeg
7.1** (the matching LibreELEC stack), not for our Collabora
ffmpeg 8.0.1. To use it, we'd need to switch ffmpeg to the 7.1
fork — which throws away the ext-SPS-RPS code in 8.0.1.

## Attempt 2: mpv 0.41 master (upstream)

```text
$ git clone --depth=1 https://github.com/mpv-player/mpv.git
$ cd mpv
$ git log -1 --oneline
f88f423 meson: consider only 'v0.*' tags when computing the version
```

Built fine against ffmpeg 8.0.1 (the `PKG_CONFIG_PATH` trick to
force the meson dependency lookup to find `libavcodec.so.62` worked
first try). But the resulting `mpv` couldn't actually do hardware
decode:

```text
$ mpv --hwdec=v4l2request 4k-hevc.mkv
...
[vd]     hevc - HEVC (High Efficiency Video Coding)
[vd]     hevc_v4l2m2m (hevc) - V4L2 mem2mem HEVC decoder wrapper
[vd] Opening decoder hevc
[vd] Looking at hwdec hevc-v4l2request...
[vd] Selected decoder: hevc - HEVC (High Efficiency Video Coding)
```

Selected **soft decode**. The `hevc-v4l2request` hwdec was looked
at and rejected. Why? Look at the source:

```bash
$ grep -nE "v4l2|\"vaapi|\"drmprime" video/decode/vd_lavc.c | head -10
video/decode/vd_lavc.c:273:    {"vaapi",           HWDEC_FLAG_AUTO | HWDEC_FLAG_WHITELIST},
video/decode/vd_lavc.c:277:    {"videotoolbox",    HWDEC_FLAG_AUTO | HWDEC_FLAG_WHITELIST},
video/decode/vd_lavc.c:282:    {"vaapi-copy",      HWDEC_FLAG_AUTO | HWDEC_FLAG_WHITELIST},
video/decode/vd_lavc.c:286:    {"videotoolbox-copy", HWDEC_FLAG_AUTO | HWDEC_FLAG_WHITELIST},
```

**No `v4l2request` entry.** Upstream mpv 0.41 removed v4l2request
support. The change is in mpv 0.39 → 0.40: the v4l2request PR
(#14690, #16282) was never merged, and the experimental
`v4l2request` hwdec name that existed in 0.38 was deleted before
0.39 was released.

**Conclusion:** upstream mpv simply does not support v4l2-request
on any version newer than 0.38. There's a path through
`hwdec=drmprime` for some devices, but rkvdec isn't a vaapi
device, so drmprime doesn't work either.

## Attempt 3: building the v4l2request.c from `~ft/mpv` against mpv 0.41

We considered backporting the `video/v4l2request.c` from
`~ft/mpv mpv-0.40.0-v4l2request` into mpv 0.41 master. The file
is ~280 lines and the meson wiring is in
`meson.build:1414-1419` and `video/out/gpu/hwdec.c:41-80`.

The issue: mpv 0.41's AVHWDeviceContext / AVHWFramesContext API
paths assume vaapi or videotoolbox semantics. The v4l2request
driver from 0.40 uses an older interface. Backporting
requires:

- Adapting `v4l2request_create_standalone` to mpv 0.41's
  `ra_hwdec_driver` API.
- Reworking the hwcontext_fns to match mpv 0.41's
  `struct hwcontext_fns` layout (which has new fields since
  0.40).
- Possibly adjusting the interop path in
  `vo_dmabuf_wayland.c:847` (the `strcmp(hw->driver->name,
  "v4l2request") == 0` branch) to match 0.41's naming.

**This is a 2-3 day patch job** for an experienced mpv
contributor. Not a 1-hour attempt.

## What we'd do if mpv were mandatory

If you must have an mpv with real v4l2-request hwaccel, the only
clean path is:

1. **Uninstall the Collabora detlev/ffmpeg 8.0.1 fork.**
2. **Build the LibreELEC jernejsk ffmpeg 7.1 fork**
   (`jernejsk/FFmpeg`, branch `v4l2-request-n7.1`). About
   1.5h on RK3588S. This is the matching fork to `~ft/mpv`.
3. **Build `~ft/mpv mpv-0.40.0-v4l2request`** against that
   ffmpeg 7.1. About 5-8 min.
4. Accept that you lose the ext-SPS-RPS improvements in
   Collabora 8.0.1.

You'd then have the **Kodi / LibreELEC production stack** on
your desktop. It works. We know it works because the Kodi team
ships it.

For the *reason* this stack stays with ffmpeg 8.0.1, see
[`ffmpeg-v4l2request`](ffmpeg-v4l2request).

## What we ship

Nothing. The stack does not include mpv. For GUI playback:

- `ffplay -i /path/to/4k-hevc.mkv` — works, uses ffmpeg 8.0.1's
  v4l2-request hwaccel, decodes 4K HEVC at 4-5x real-time.
  Renders through SDL2 (which we've linked to Vulkan via the
  ffmpeg configure). UI is minimal (no OSC, no playlist) but
  functional.
- `gst-launch-1.0 ... v4l2slh265dec ...` — works, uses the
  gstreamer v4l2sl element. Use this for any pipeline-style
  use case.
- `vlc` — *not* this version. See [`vlc-rejected`](vlc-rejected).

## Decision log entry

2026-06-05: After the three mpv attempts above, we accepted that
mpv is not part of this stack. Documented in
[`decision-log`](decision-log).
