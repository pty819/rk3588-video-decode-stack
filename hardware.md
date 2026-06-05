# Hardware

> What kernel, what driver, what UAPI. The exact version of everything
> this stack targets, plus what changed between 5.10 vendor kernels
> and 7.0+ mainline.

## Verified on this box

```text
uname -r:        7.0.11-edge-rockchip64
SoC:             Rockchip RK3588S
RAM:             7.8 GiB total, 5.2 GiB available
swap:            13 GiB
GPU:             Mali-G610 (Mesa 25.2.8, Vulkan 1.4.318 via panvk)
CMA:             524288 KiB (CmaTotal) — `extraargs=cma=512M` in /boot/armbianEnv.txt
VPU:             VDPU381 (rkvdec2) — driven by upstream `rockchip-vdec.ko`
DTS node:        /dev/video1 = rkvdec (Boris Brezillon/Collabora)
```

## The stateless stack: what's in the kernel

| Component | Kernel module | What it does |
|---|---|---|
| `rockchip-vdec.ko` | `drivers/staging/media/rkvdec2` (upstream) | State machine for VDPU381 |
| `rockchip-vdec-core.ko` | `drivers/staging/media/rockchip/vdec` | Codec control, BBreickwald |
| `videobuf2-core.ko` | `drivers/media/common/videobuf2` | Buffer framework |

The driver exposes two sets of formats:

- **Output (to the kernel)**: parsed slice data in `V4L2_PIX_FMT_HEVC_SLICE_RAW` /
  `V4L2_PIX_FMT_H264_SLICE_RAW` (and similar for vp8, vp9, av1, mpeg2).
  This is the **stateless** API — the kernel gets the pre-decoded slice
  headers, not the full bitstream.
- **Capture (from the kernel)**: decoded frames in `V4L2_PIX_FMT_BGRX32` or
  in a DRM PRIME format like `V4L2_PIX_FMT_NV12` plus DRM handle.

The combination of those two formats and the `V4L2_BUF_FLAG_REQUEST_FD`
flag is what makes a decoder **stateless**: every submitted output buffer
carries a request FD pointing at the parsed slice data, and the kernel
rejects the request if its dependencies aren't satisfied. A bug in the
dependency graph means a frame is dropped, not a kernel panic.

## What changed between 5.10 and 7.0+

### 5.10 vendor kernel (BSP)

The vendor kernel ships `mpp_service` (`/dev/mpp_service`), a Rockchip-
proprietary userspace driver that talks to the VPU via an ioctl protocol
not in mainline. It supports both decode and encode, both stateless and
stateful. The catch:

- The kernel is end-of-life for new hardware support.
- `mpp_service` is **not in mainline** and probably never will be.
- For RK3588 specifically, the vendor mpp has limited HEVC 4K
  performance compared to the mainline driver.

### 6.x and 7.0+ mainline

The mainline driver (`rockchip_vdec2`, later moved to `rkvdec2`) is a
clean stateless implementation. It uses the upstream V4L2 M2M
framework and follows the same patterns as Allwinner Cedrus and
Amlogic V4L2 drivers.

The catch: **the upstream UAPI has evolved** as more HEVC features
landed. Specifically:

- The `hevc_ext_sps_*_rps` UAPI structs (for short-term reference
  picture set signaling) are a 7.0+ addition. They were added because
  the original `hevc_dec_ctrl_param` struct couldn't represent
  certain HEVC stream features that show up in BluRay rips and
  10-bit HEVC content.
- The Collabora detlev/ffmpeg 8.0.1 fork has the `hevc_ext_sps_*_rps`
  code paths in `libavcodec/v4l2_request_hevc.c`. The earlier
  LibreELEC jernejsk 7.1 fork has them too, but the API is slightly
  different.

**For a clean box on 7.0+ mainline, you need ffmpeg that knows about
`hevc_ext_sps_*_rps`. That's why the Collabora 8.0.1 fork is the
right choice** — the LibreELEC 8.0 fork is 23 months stale, and the
Collabora 7.1 branch is older still.

## CMA — the silent requirement

`rockchip-vdec` allocates internal buffers from CMA. The default CMA
size in the armbian kernel config is 128 MiB, which is enough for 720p
and most 1080p content but not for 4K HEVC Main profile (10-bit, B
frames, complex RPS).

For 4K HEVC Main profile 8-bit, 4K HEVC Main 10, or 4K AV1, set:

```text
# /boot/armbianEnv.txt
extraargs=cma=512M
```

Then verify:

```bash
$ grep CmaTotal /proc/meminfo
CmaTotal:        524288 kB
```

**Do not** increase CMA past 1G without testing — it competes with
the GPU for memory and can cause Wayland compositor hiccups.

## S264 / S265 — what the kernel actually calls them

When ffmpeg submits a parsed slice buffer, the kernel logs the
"stream format" as S264 (H.264) or S265 (HEVC). That's where the
`Using V4L2 media driver rkvdec (7.0.11) for S265` log line comes
from. **If you don't see "for S265" in the log, you're not actually
on the stateless path** — even if the decoder name says
`hevc_v4l2request`, the kernel may have rejected the format and
fallen back to a different driver.

## What's *not* in this stack

- **VA-API** for the rkvdec. The `rockchip-vaapi` driver from woodyst
  uses a different code path (stateful M2M with the vendor mpp).
  It can decode 4K but at lower frame rate and without the
  ext-SPS-RPS improvements. Out of scope here.
- **Hardware encoding**. The RK3588 has VEP (encoder), but the
  upstream rkvdec2 driver is decode-only.
- **JPEG / VP6 / VC-1**. We didn't test; mpv 0.37 lists them as
  supported by `v4l2m2m` but the rkvdec hardware doesn't do all of
  them. If you need them, verify before relying on the stack.

## Decision points (full evidence in [`decision-log`](decision-log))

1. **Mainline 7.0.11 kernel, not vendor 5.10** — vendor is EOL, the
   mainline driver has more active work, and the ext-SPS-RPS
   improvements only exist on mainline.
2. **Collabora 8.0.1 fork, not LibreELEC 8.0 fork** — Collabora is
   5 months stale vs LibreELEC's 23 months, and carries the
   ext-SPS-RPS code.
3. **Coexistence with apt ffmpeg 6.1.1** — different SONAMEs (60 vs
   62), no conflict, no need for `LD_LIBRARY_PATH` shenanigans.
4. **No mpv** — the GUI player story is unsolved. Documented in
   [`mpv-rejected`](mpv-rejected) so the next attempt doesn't repeat
   the work.
