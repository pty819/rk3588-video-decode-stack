# Motivation

> Why this stack isn't "just install ffmpeg 8 from the apt repo."

This page explains the problem in one sentence, then expands on each
piece of the failure. The full evidence (git refs, kernel UAPI numbers,
verified test logs) is in [Hardware](hardware) and
[`decision-log`](decision-log).

## The sentence

Apt's ffmpeg 6.1.1 on armbian noble 24.04 (aarch64) cannot do real
hardware-accelerated 4K HEVC decode on an RK3588S running mainline
kernel 7.0+, because the v4l2-request hwaccel patch exists in exactly
two non-upstream forks (Collabora and LibreELEC) and neither is packaged
in any Ubuntu release.

## Three failure modes for the obvious "just upgrade" answer

### 1. `apt install ffmpeg` doesn't help

The noble noble pocket has **only** ffmpeg 6.1.1. There is no
ffmpeg 7.x or 8.x backport, no PPA with the v4l2-request patch, no
`ffmpeg-v4l2request` apt package, and Ubuntu's official backports
policy is conservative enough that you'll be waiting years.

Upstream ffmpeg's mainline does not have v4l2-request support either:
PR #20847 ("lavc/v4l2: request API h264/hevc/mpeg2/vp8/vp9/av1
hwaccel") has been in review since 2024-08 with no merge commit. The
upstream maintainers' position is "we need a clear test matrix and a
naming consensus before we can land it."

### 2. `apt remove ffmpeg` to swap in something else doesn't work

You'd think: "I can just `apt remove ffmpeg` and replace it with the
fork I built." On a KDE Plasma desktop, **don't**:

```text
$ apt-get -s remove ffmpeg
The following packages will be REMOVED:
  ffmpeg kwin-wayland plasma-workspace plasma-workspace-bin ...
```

The `apt` dependency solver treats `ffmpeg` as a "core multimedia
library" and `kwin-wayland`, `plasma-workspace`, `pipewire`, and
`qt6-multimedia` all want `libavcodec60`. The only safe path is
**coexistence** — install the fork to `/usr/local` with a different
SONAME, keep the apt ffmpeg 6.1.1 + its libs (`libavcodec.so.60`)
on hold.

### 3. `apt install mpv` is the wrong player for this stack

Apt's mpv 0.37.0-1ubuntu4 is dynamically linked against
`libavcodec.so.60` — **the apt ffmpeg 6.1.1 ABI**. It cannot link
against `libavcodec.so.62` (the fork's SONAME) without a rebuild,
and the only way to do that is recompile mpv from source. We tried
that; see [`mpv-rejected`](mpv-rejected).

## What the right answer actually looks like

Three things compiled from upstream, no fork churn at runtime:

1. **ffmpeg 8.0.1** — Collabora `detlev/ffmpeg`,
   branch `v4l2-request-ext-sps-rps-n8.0.1`, HEAD `dfa10f6 wip: fix st rps`
   (2026-01-15). Installed to `/usr/local`, SONAME `libavcodec.so.62`.
2. **libplacebo 7.360.1** — upstream tag, because mpv 0.41 requires
   `>= 7.360.1`. Built with default options, including `vulkan` +
   `shaderc` (the only consumer of libplacebo in this stack is mpv;
   ffmpeg's `--enable-libplacebo` worked fine against 6.338.2 but we
   want one libplacebo in the build).
3. **gstreamer1.0** — apt's 1.24.2 is good enough. The `v4l2sl*`
   elements for stateless decode are already there.

`pipewire`, `kwin-wayland`, `qt6-multimedia` keep their existing
`libavcodec.so.60` linkage. Nothing on the apt side moves.

## Why not also rebuild mpv?

We tried. Three different mpv source trees, three different failure
modes — all documented in [`mpv-rejected`](mpv-rejected). The
short version: upstream mpv 0.41 dropped v4l2-request support; the
LibreELEC `~ft/mpv` v4l2request fork is frozen at mpv 0.40 + ffmpeg
7.x; the only working combo requires rebuilding ffmpeg 7.x, which
throws away the v4l2-request ext-SPS-RPS improvements the 8.0.1
Collabora fork carries.

For now, this stack provides an ffmpeg that **actually does** real
hardware decode. Use `ffplay` for any GUI. If you need a real mpv,
the path is described (and warned about) in [`mpv-rejected`](mpv-rejected).

## What you get after the install

| Path | Binary | ABI | Hard decode path |
|---|---|---|---|
| `/usr/local/bin/ffmpeg` | ffmpeg 8.0.1 | `libavcodec.so.62` | `v4l2request` hwaccel → rkvdec2 S265 |
| `/usr/bin/ffmpeg` | ffmpeg 6.1.1 (apt, held) | `libavcodec.so.60` | `v4l2m2m` stateful (broken on 7.0+ — see [`troubleshooting`](troubleshooting)) |
| `/usr/local/bin/ffprobe` | ffprobe 8.0.1 | `libavcodec.so.62` | n/a |
| `/usr/local/bin/ffplay` | ffplay 8.0.1 | `libavcodec.so.62` | uses ffmpeg 8.0.1's hwaccel |
| `/usr/bin/mpv` | — | — | not installed (we tried, see [`mpv-rejected`](mpv-rejected)) |

For real 4K HEVC verification, see [`verify`](verify).
