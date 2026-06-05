# RK3588 Video Decode Stack

A reproducible recipe to get **real 4K HEVC hardware decode** working on a
Rockchip RK3588 / RK3588S running mainline Linux kernel 7.0+ — built around
the upstream `v4l2-request` (stateless) decoder API and `rkvdec2` (VDPU381)
hardware.

This site documents one successful end-to-end configuration and the failed
attempts that led to it. Every command, patch, and verifier is included.
Nothing here is hand-waved; the `.sh` scripts in the [`verify-scripts/`](verify-scripts/index)
directory are the same scripts used to prove the build is real, not
"looks fine, ship it".

## What's actually in the box

After following [Install](install), your Orange Pi 5 / RK3588S will have:

- `ffmpeg 8.0.1` (Collabora `detlev/ffmpeg` v4l2-request-ext-sps-rps-n8.0.1)
  installed in `/usr/local` with all six v4l2-request hwaccels compiled in.
  Replaces the apt ffmpeg 6.1.1 only at the binary level (different SONAME
  — they coexist; apt's ffmpeg is held to keep `pipewire` and `qt6-multimedia`
  happy).
- `libplacebo 7.360.1` compiled from upstream tag, since mpv 0.41 requires
  `>= 7.360.1` and noble only ships `6.338.2`.
- The apt-installed `gstreamer1.0` packages, which already include the
  `v4l2sl` (stateless) elements and are good enough for most use cases.
- **No mpv.** See [`mpv-rejected`](mpv-rejected) for the full story: the
  upstream mpv 0.41 removed v4l2-request support, the `~ft/mpv` v4l2request
  fork is frozen at mpv 0.40 + ffmpeg 7.x API (incompatible with ffmpeg 8),
  and the only working combo would be a 1.5-hour ffmpeg 7.x rebuild.
  This stack ships the working ffmpeg + works under `ffplay` (built from
  the same ffmpeg) for any actual video display.

## Quick verification

If you already have the stack installed, one command confirms it's real:

```bash
ffmpeg -v info -hwaccel v4l2request -hwaccel_output_format drm_prime \
  -i /path/to/4k-hevc-clip.mkv -f null -
```

You should see:

```
[AVHWFramesContext @ 0x...] Using V4L2 media driver rkvdec (7.0.11) for S265
Stream #0:0 -> #0:0 (hevc (native) -> wrapped_avframe (native))
frame=... ... speed=4.6x ...    # ~4-5x on RK3588S, real VPU work
```

If the `rkvdec ... S265` line is missing, you've hit a soft fallback and
the CPU is doing the work — see [`troubleshooting`](troubleshooting).

## How to read this site

::::{grid} 1 1 2 2
:gutter: 3

:::{grid-item-card} {octicon}`book;1.5em;sd-mr-1` Motivation
:link: motivation
:link-type: doc

Why the apt stack doesn't work, what problem v4l2-request solves, and why
this isn't a "just upgrade" situation.
:::

:::{grid-item-card} {octicon}`cpu;1.5em;sd-mr-1` Hardware
:link: hardware
:link-type: doc

The exact kernel / driver / UAPI this stack targets, and what changed
between 5.10 vendor kernels and 7.0+ mainline.
:::

:::{grid-item-card} {octicon}`package;1.5em;sd-mr-1` Stack components
:link: ffmpeg-v4l2request
:link-type: doc

What each of the four pieces (ffmpeg, libplacebo, gstreamer, mpv) does
and why each is the version it is.
:::

:::{grid-item-card} {octicon}`tools;1.5em;sd-mr-1` Install
:link: install
:link-type: doc

Step-by-step recipe — apt deps, configure, the one-line libplacebo patch,
install to `/usr/local`, hold the apt libs, verify.
:::

:::{grid-item-card} {octicon}`alert;1.5em;sd-mr-1` Troubleshooting
:link: troubleshooting
:link-type: doc

What we got wrong, the three mpv fork dead-ends, the libplacebo API
drift, the HEVC ST RPS wip bug.
:::

:::{grid-item-card} {octicon}`history;1.5em;sd-mr-1` Decision log
:link: decision-log
:link-type: doc

A time-ordered log of what we tried, what failed, what we kept.
:::

::::

## Why this isn't on Read the Docs

Sphinx-rendered output is checked in under `_build/html/`, so you can read
the site locally without network. The GitHub Pages deployment is wired up
in `.github/workflows/docs.yml` and triggers on every push to `main`.
