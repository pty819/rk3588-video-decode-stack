# Decision log

> A time-ordered log of what we tried, what failed, what we kept.
> One entry per significant decision point. The 4 entries here
> cover the 2 weeks of work that produced the current stack.

## 2026-05-30 — Initial scope, mpv fork decision

**Context:** Started the project to get 4K HEVC hardware decode
working on an Orange Pi 5 (RK3588S) running armbian 7.0.11-edge
mainline kernel. The user's existing setup was: apt ffmpeg
6.1.1, apt mpv 0.37, KDE Plasma Wayland, pipewire.

**Investigated:**

- **Upstream FFmpeg.** PR #20847 (v4l2-request hwaccel) in
  review since 2024-08. Not merged. Not viable.
- **Collabora detlev/ffmpeg.** v4l2-request branch exists,
  6 codec hwaccels, active commits through 2025-12.
- **LibreELEC jernejsk/FFmpeg.** v4l2-request-n7.1 branch,
  similar scope. Older API, but stable.
- **LibreELEC ~ft/ffmpeg.** v4l2request-8.0-rkvdec branch,
  same scope as Collabora. Less active.
- **Kodi stack.** Production use of LibreELEC jernejsk
  ffmpeg + ~ft/mpv. Working today.

**Decided:** Collabora detlev/ffmpeg. Reasons:

- HEVC ext-SPS-RPS UAPI support (newer than LibreELEC 7.1)
- Active development in late 2025 (more recent than
  LibreELEC 8.0)
- Single project for ffmpeg (vs. jernejsk FFmpeg + ~ft/mpv
  fork pair)

**Outcome:** Correct. The Collabora 8.0.1 fork decodes
4K HEVC Main 8-bit and 1080p H.264 with real VPU work.

## 2026-06-04 — RK3588S baseline established

**Context:** Confirmed the hardware/driver stack on this
specific box.

**Established:**

- Kernel `7.0.11-edge-rockchip64` (mainline)
- `/dev/video1` = rkvdec2, driven by upstream
  `rockchip-vdec.ko` (Boris Brezillon)
- CMA 524288 KiB (set in `/boot/armbianEnv.txt`
  `extraargs=cma=512M`)
- Mali-G610 GPU with Mesa 25.2.8 panvk Vulkan 1.4.318
- 8 GiB RAM, 13 GiB swap

**apt ffmpeg 6.1.1 verified broken for 4K HEVC:**

- `ffmpeg -decoders | grep v4l2`: only `h264_v4l2m2m`,
  `hevc_v4l2m2m`, etc. (stateful). No `*_v4l2request`.
- `ffmpeg -hwaccels`: empty.
- `apt remove ffmpeg --simulate`: cascades into
  kwin-wayland and the entire plasma desktop. **Cannot
  remove apt ffmpeg.**

**apt mpv 0.37 verified broken:**

- `mpv --hwdec=v4l2m2m`: `Unsupported hwdec: v4l2m2m` in
  mpv 0.37. Must use `v4l2m2m-copy`.
- `mpv --hwdec=v4l2m2m-copy`: still calls
  `hevc_v4l2m2m` (stateful, not v4l2request), which
  fails on 7.0+ mainline: `Could not find a valid device`.

**Outcome:** Confirmed that no apt-provided stack works
on this box for 4K HEVC. Either rebuild ffmpeg or accept
software decode.

## 2026-06-05 — Collabora detlev/ffmpeg 8.0.1 built and installed

**Context:** Built and installed the Collabora detlev/ffmpeg
8.0.1 fork with v4l2-request hwaccel.

**Built:**

- HEAD `dfa10f6 wip: fix st rps` (2026-01-15)
- Branch `v4l2-request-ext-sps-rps-n8.0.1`
- Configure: see [`install`](install)
- One-line patch: `PL_ALPHA_NONE` → `PL_ALPHA_UNKNOWN` in
  `libavfilter/vf_libplacebo.c:940` (see
  [`libplacebo-api-drift`](libplacebo-api-drift))

**Build time:** 25 minutes on RK3588S, `-j8`.

**Installed to `/usr/local`** with `--enable-shared`. Coexists
with apt ffmpeg 6.1.1 (different SONAMEs, no conflict).

**Held 8 apt packages** to prevent patch-level upgrades
that could break `pipewire` / `qt6-multimedia`:
`ffmpeg libavcodec60 libavdevice60 libavfilter9 libavformat60
libavutil58 libswresample4 libswscale7`.

**Verified:**

- 4K HEVC: `Using V4L2 media driver rkvdec (7.0.11) for
  S265`, `speed=4.62x` real-time.
- 1080p H.264: `Using V4L2 media driver rkvdec (7.0.11) for
  S264`, `speed=12.3x` real-time.
- Verify script: 5/5 checks pass.

**Outcome:** Stack is functional for 4K HEVC, 1080p H.264.
Loss of mpv as a GUI is documented in
[`mpv-rejected`](mpv-rejected). Loss of VLC is documented
in [`vlc-rejected`](vlc-rejected).

## 2026-06-05 — Three mpv attempts, all rejected

**Context:** Tried to add mpv to the stack. Failed three times.

**Attempt 1: ~ft/mpv mpv-0.40.0-v4l2request.**

```text
$ git clone --branch=mpv-0.40.0-v4l2request https://git.sr.ht/~ft/mpv
$ cd mpv
$ meson setup build -Dv4l2request=enabled ...
$ ninja -C build
../demux/demux_mkv.c:2203:32: error: use of undeclared identifier 'FF_PROFILE_ARIB_PROFILE_A'
../demux/demux_mkv.c:2209:32: error: use of undeclared identifier 'FF_PROFILE_ARIB_PROFILE_C'
```

**Failure:** the `~ft/mpv` fork is frozen at mpv 0.40 + ffmpeg
7.x. ffmpeg 8.0 renamed `FF_PROFILE_ARIB_PROFILE_*`. Fork
won't build against ffmpeg 8.0.1.

**Attempt 2: mpv 0.41 master.**

```text
$ git clone --depth=1 https://github.com/mpv-player/mpv.git
$ cd mpv
$ meson setup build ... # PKG_CONFIG_PATH=/usr/local/lib/.../pkgconfig
$ ninja -C build
# Builds successfully.
$ sudo ninja -C build install
$ mpv --hwdec=v4l2request 4k-hevc.mkv
[vd] Selected decoder: hevc - HEVC (High Efficiency Video Coding)  # soft decode
```

**Failure:** upstream mpv 0.41 removed v4l2request support.
The hwaccel machinery in the source has `vaapi`,
`vaapi-copy`, `videotoolbox`, `videotoolbox-copy`,
`drmprime`, `drmprime-overlay` — no `v4l2request`. The
failing builds are not visible in the user's view; mpv
silently uses soft decode.

**Attempt 3: VLC 3.0.20 from apt.**

```text
$ apt install vlc
$ vlc --list-modules | grep v4l2
libv4l2_plugin.so  # input device, not decoder
# (no v4l2-request decoder)
$ vlc --avcodec-hw v4l2-request 4k-hevc.mkv
# Runs but CPU 100%, software decode.
```

**Failure:** noble apt vlc 3.0.20 was built without
`--enable-v4l2-request`. Even if it had it, VLC would use
apt's ffmpeg 6.1.1 (libavcodec.so.60), not our 8.0.1
(libavcodec.so.62), so the v4l2-request hwaccel we built
would never be loaded.

**Decided:** Ship the stack without mpv. Document
[`mpv-rejected`](mpv-rejected) and
[`vlc-rejected`](vlc-rejected) so the next attempt
doesn't repeat the work.

**Outcome:** Stack is final as of 2026-06-05. No further
work planned unless a BluRay-rip-capable fix is needed
(see [`known-bugs`](known-bugs)).

## What we'd do differently

If we were starting over, we'd skip the mpv detour
entirely. The three attempts cost 3 hours of compile
time (most of it on the `~ft/mpv` build, which takes
5-8 minutes on RK3588S) plus reading mpv source code.
That's time we could have spent on edge cases in the
ffmpeg stack.

The signal we missed: when an upstream project (mpv)
has *no* recent v4l2 commits, it's not "they forgot to
add it" — it's "they chose not to." Reading the
rejection history of PR #14690 would have saved us
attempt 1.
