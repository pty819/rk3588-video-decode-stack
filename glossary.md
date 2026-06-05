# Glossary

> The terms that show up in ffmpeg / kernel / Collabora blog posts
> without explanation. If something here is wrong, fix it — these
> definitions are used across the rest of the site.

## Stateless vs stateful

| Term | Meaning | Kernel API |
|---|---|---|
| **Stateful** | The driver keeps a copy of the reference frame buffer list between frames. The user (ffmpeg) hands the driver a full encoded frame and trusts the driver to maintain the DPB correctly. | `VIDIOC_ENUM_FMT` returns bitstream formats; `VIDIOC_G_CTRL` set + `VIDIOC_DECODER_CMD` start. Old V4L2 M2M API. |
| **Stateless** | The driver does not keep any state between frames. The user (ffmpeg) parses the slice headers itself, builds the DPB description, and hands the driver a parsed slice + DPB context per frame. | `V4L2_BUF_FLAG_REQUEST_FD` + the `hevc_ext_sps_*_rps` / `hevc_dec_param` controls. Newer V4L2 M2M API. |

Stateful is easier to wire up (ffmpeg's `hevc_v4l2m2m` decoder is
stateful) but has two real problems on RK3588S + 7.0+ mainline:

1. The vendor 5.10 driver accepted stateful M2M, but the 7.0+
   driver is stateless-only for the high-bitrate modes (4K HEVC Main
   10, BluRay rips).
2. Stateful can't recover from reference frame errors — a single
   corrupted reference poisons the entire DPB until you reset.

Stateless is what we want. It needs the `v4l2request` hwaccel in
ffmpeg, which is the entire point of this stack.

## `v4l2m2m` vs `v4l2request` vs `v4l2sl`

Three names you'll see in error messages, four in the apt manpages.

| Name | What it is | Decoder name in ffmpeg | Kernel API |
|---|---|---|---|
| `v4l2m2m` | A ffmpeg decoder wrapper that talks to a V4L2 mem-to-mem device | `hevc_v4l2m2m`, `h264_v4l2m2m`, ... | Stateful. Pre-2020. |
| `v4l2request` | A ffmpeg **hwaccel** that drives the stateless path | n/a (hwaccel, not a decoder) | Stateless with `V4L2_BUF_FLAG_REQUEST_FD`. |
| `v4l2sl` (gstreamer element) | GStreamer's stateless decoder elements | n/a (gstreamer) | Stateless. |

The relationship:

```
v4l2m2m          ─┐
                   ├── both talk to the same /dev/videoN device
v4l2request       ─┤   (one per hardware codec instance)
v4l2sl (gstreamer) ┘
```

You'd think `v4l2m2m` and `v4l2request` would share code. They do
in the kernel driver, but the ffmpeg-side plumbing is completely
different. That's why the v4l2request patch (now in Collabora /
LibreELEC forks) doesn't make `hevc_v4l2m2m` faster — it adds a
new path, not a fix.

## RPS, SPS, VPS, PPS

HEVC syntax elements you'll see in error messages.

| Acronym | Full name | What it does |
|---|---|---|
| VPS | Video Parameter Set | Stream-wide properties (layer, sub-layer, timing). One per stream. |
| SPS | Sequence Parameter Set | Per-sequence properties (resolution, chroma format, bit depth, codec profile). One or more per stream. |
| PPS | Picture Parameter Set | Per-picture group properties (transform mode, SAO, sign-data hiding). Many per stream. |
| RPS | Reference Picture Set | The list of reference frames used to decode the current picture. **Per picture.** |

`v4l2request` + the new `hevc_ext_sps_*_rps` UAPI is about
handing the RPS to the kernel explicitly, because the original
UAPI couldn't represent the short-term RPS in certain HEVC
streams. If you've ever seen a kernel error like
`failed to set hevc_ext_sps_st_rps: -EINVAL`, that's the bug.
The Collabora detlev/ffmpeg `wip: fix st rps` HEAD is working
through this; see [`known-bugs`](known-bugs).

## S264 / S265

The kernel's internal name for the parsed H.264 / HEVC slice
formats. You'll see them in log lines like
`Using V4L2 media driver rkvdec (7.0.11) for S265`.

If a log line ends with `... for S264` or `... for S265`, you're
on the stateless path. If it ends with `... for HEVC` or
`... for H.264`, you're on the legacy stateful path. The
Collabora fork's `Using V4L2 media driver rkvdec for S265`
confirmation is the canonical "real hardware decode" check.

## SONAME

The library version embedded in `libavcodec.so.<X>`. Two ffmpegs
can coexist on the same box if their SONAMEs differ:

- `/usr/lib/aarch64-linux-gnu/libavcodec.so.60.x` — apt ffmpeg 6.1.1
- `/usr/local/lib/aarch64-linux-gnu/libavcodec.so.62.x` — self-built
  ffmpeg 8.0.1

`ldd $(which ffmpeg)` shows which one wins. The `/usr/local/lib/...`
path appears earlier in `ldconfig`'s search order, so the self-
built binary picks up its own libs and the apt ffmpeg picks up the
apt libs. **No `LD_LIBRARY_PATH` needed.**

## CMA

Contiguous Memory Allocator. The Linux kernel's way of allocating
a single contiguous physical block for hardware that can't do
scatter-gather DMA. The rkvdec uses CMA for reference frame
storage. Default size on armbian is 128 MiB; you need 512 MiB for
4K HEVC.

## panvk

The open-source Vulkan driver for ARM Mali GPUs, in Mesa. On
RK3588S, the G610 is a "Bifrost" gen 4 GPU. The Mesa panvk
driver is good for compute (we measured 909/2120 MFLOPs on fp16
matmul in a separate project) but has quirks around Vulkan 1.4
feature structs — see [`vulkan-compute-dev`](https://github.com/pty819/vulkan-lab)
for that. For this stack, panvk just needs to work for `vo=gpu`
in mpv, which it does.

## VDPU381 / rkvdec2

The decode block in RK3588S. "VDPU381" is the internal Rockchip
name; "rkvdec2" is the upstream Linux kernel name. They refer to
the same hardware. Supports H.264, HEVC (Main + Main 10), VP9, AV1
decode in hardware, 4K@60 for H.264/HEVC/VP9 and 4K@30 for AV1.

## ext-SPS-RPS

The "extended SPS" feature of HEVC that carries additional RPS
information beyond what fits in the original UAPI. Required
for some HEVC Main 10 streams and many BluRay rips. The
`hevc_ext_sps_*_rps` UAPI structs were added in kernel 6.x and
extended in 7.0+. The Collabora detlev/ffmpeg fork's v4l2request
code path uses them.
