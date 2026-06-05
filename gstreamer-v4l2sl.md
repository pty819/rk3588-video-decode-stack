# gstreamer — apt 1.24.2 with v4l2sl elements

> The good-enough fallback. GStreamer's `v4l2slh265dec` /
> `v4l2slh264dec` elements do the same stateless decode as ffmpeg's
> `v4l2request` hwaccel, talking to the same kernel device, and
> they're already in the apt packages on armbian noble.

## What you get from apt

```bash
$ dpkg -l gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
ii  gstreamer1.0-plugins-good   1.24.2-1ubuntu0.2 arm64
ii  gstreamer1.0-plugins-bad    1.24.2-1ubuntu0.2 arm64
```

`gstreamer1.0-plugins-bad` contains the v4l2sl elements:

```bash
$ gst-inspect-1.0 | grep v4l2sl
v4l2sl:  v4l2slh264dec: V4L2 stateless H264 decoder
v4l2sl:  v4l2slh265dec: V4L2 stateless H265 decoder
v4l2sl:  v4l2slvp8dec:  V4L2 stateless VP8 decoder
v4l2sl:  v4l2slvp9dec:  V4L2 stateless VP9 decoder
```

**Six codec decoders in ffmpeg, four in gstreamer** (no AV1, no
MPEG-2 in gstreamer's v4l2sl — those are in `v4l2` (stateful)
elements in different plugins).

## Pipeline: play a 4K HEVC file

```bash
gst-launch-1.0 -v filesrc location=4k-hevc.mkv ! \
  matroskademux ! h265parse ! v4l2slh265dec ! \
  videoconvert ! waylandsink
```

If the v4l2sl decoder is the only path, the pipeline simplifies
to just the decode element. The matroskademux → h265parse →
v4l2slh265dec sequence is what you'd use for an MKV container;
for a raw H.265 elementary stream, drop the demuxer.

## Verifying it actually decodes

```bash
$ gst-launch-1.0 -v filesrc location=4k-hevc.mkv ! \
    matroskademux ! h265parse ! v4l2slh265dec ! fakesink
Setting pipeline to PAUSED ...
Pipeline is PREROLLING ...
/GstPipeline:pipeline0/GstV4l2SlH265Dec:v4l2slh265dec0.GstPad:src: caps = "video/x-raw\,format=NV12\,width=3840\,height=2160\,framerate=30/1"
Pipeline is PREROLLED ...
Setting pipeline to PLAYING ...
```

The `caps = "video/x-raw\,format=NV12..."` line is the
gstreamer-side proof: the decoded frame is being produced. For
real hardware confirmation, look at:

```bash
$ cat /sys/devices/platform/ff9a0000.video-codec/load 2>/dev/null
# or
$ cat /sys/kernel/debug/rkvdec/load 2>/dev/null
```

**7.0+ mainline kernel may not expose the load counter** —
it was added in 5.10 vendor and not always carried into mainline.
If neither path exists, the only verification is the gstreamer
log line plus a working frame counter.

## Why not use gstreamer for everything

GStreamer's v4l2sl elements are **independent of ffmpeg's
v4l2request code path**. They share the kernel driver but not
the userspace. Concretely:

- If the ffmpeg HEVC ST RPS wip bug bites a specific stream,
  gstreamer may still decode it correctly. The ffmpeg
  implementation of the new ext-SPS-RPS UAPI is the one with
  the open issue.
- If the gstreamer pipeline has problems (e.g. a matroskademux
  issue with unusual containers), the ffmpeg `ffplay` will
  work fine.

Use whichever is closer to your use case:

- **Web browser streaming, anything WebKit-based, Electron
  apps**: ffmpeg is mandatory. Use the ffmpeg we built.
- **Native GStreamer pipeline, command-line playback, GTK
  media apps**: gstreamer is enough, and already installed.

## Verifier script

The `verify-gstreamer-v4l2sl.sh` script in
[`verify-scripts`](verify-scripts/index) runs a 4K HEVC
decode end-to-end and checks the kernel log for the
`rkvdec2 ... S265` line.

## Limitations

- The v4l2sl elements predate the ext-SPS-RPS UAPI in 7.0+.
  Whether they handle the new UAPI correctly is not
  documented; we've only tested with 4K HEVC Main profile
  8-bit content, which doesn't need ext-SPS-RPS.
- No AV1 stateless decoder in gstreamer's v4l2sl elements.
  For 4K AV1, use ffmpeg with `av1_v4l2request`.
