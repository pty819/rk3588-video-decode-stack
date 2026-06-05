# ffmpeg — Collabora detlev/ffmpeg 8.0.1

> The centerpiece of the stack. Why this fork, how to build it, what
> to watch out for.

## The choice: why Collabora, not LibreELEC, not upstream

As of June 2026, three ffmpeg sources are candidates for v4l2-request:

| Source | Branch | Last commit | Status |
|---|---|---|---|
| Upstream `FFmpeg/ffmpeg` | master | 2026-05-28 (live) | No v4l2-request. PR #20847 in review. |
| Collabora `detlev/ffmpeg` | `v4l2-request-ext-sps-rps-n8.0.1` | `dfa10f6` 2026-01-15 | 6 codec hwaccels + ext-SPS-RPS. |
| LibreELEC `~ft/ffmpeg` | `v4l2request-8.0-rkvdec` | `4b929c15` 2024-07-15 | 6 codec hwaccels. **No ext-SPS-RPS.** |

Upstream is right out. Between the two forks:

- LibreELEC is 23 months stale. Last meaningful commit was 2024-07.
- Collabora is 5 months stale. Last commit is `dfa10f6 wip: fix st
  rps` — a work-in-progress on the ext-SPS-RPS short-term RPS code
  path. The hwaccel machinery itself is stable.

We chose Collabora. The HEVC ST RPS work-in-progress is the
**only** known issue with the fork; see [`known-bugs`](known-bugs).
For 4K HEVC Main profile 8-bit, Main 10, H.264 4K, and VP9 4K
content, the Collabora fork is rock-solid.

> **How to verify a fork isn't dead.** Don't read press releases.
> Run `git ls-remote` + `git log --since=6.month --oneline | wc -l`
> on the actual branch you want to use. The Collabora blog post
> describing the VDPU381 work called the fork "preliminary" /
> "early stage" — that was the wording used for the *upstream MR
> that would integrate the work*, not for the fork itself. The
> actual git state shows 6 codec v4l2request hwaccels all
> committed, plus the ext-SPS-RPS UAPI, with one `wip:`-prefixed
> HEVC ST RPS bug. See [`fork-survey`](fork-survey) for the
> verifiable evidence.

## What's in the build

Six v4l2-request hwaccels, enabled by default in
`ffbuild/config.mak`:

| Codec | ffmpeg name | `ffmpeg -hwaccels` shows | `ffmpeg -decoders` shows |
|---|---|---|---|
| H.264 | `h264_v4l2request` hwaccel | `v4l2request` | `h264_v4l2m2m` (codec wrapper) |
| HEVC | `hevc_v4l2request` hwaccel | `v4l2request` | `hevc_v4l2m2m` |
| VP8 | `vp8_v4l2request` hwaccel | `v4l2request` | `vp8_v4l2m2m` |
| VP9 | `vp9_v4l2request` hwaccel | `v4l2request` | `vp9_v4l2m2m` |
| AV1 | `av1_v4l2request` hwaccel | `v4l2request` | `av1_v4l2m2m` |
| MPEG-2 | `mpeg2_v4l2request` hwaccel | `v4l2request` | `mpeg2_v4l2m2m` |

The v4l2request hwaccel **rides on** the codec wrappers; it doesn't
introduce new decoder names. That's important for verification —
see [`verify`](verify).

## Configure flags that actually work

After a few iterations of "this flag doesn't exist" and "this flag
is removed in this version" failures, the working configure
invocation is:

```bash
./configure \
  --prefix=/usr/local \
  --libdir=/usr/local/lib/aarch64-linux-gnu \
  --shlibdir=/usr/local/lib/aarch64-linux-gnu \
  --enable-shared --disable-static \
  --enable-gpl --enable-version3 --enable-nonfree \
  --enable-libplacebo --enable-libshaderc \
  --enable-libx264 --enable-libx265 \
  --enable-libvpx --enable-libaom --enable-libdav1d \
  --enable-libfdk-aac --enable-libmp3lame \
  --enable-libopus --enable-libvorbis --enable-libtheora \
  --enable-libcodec2 --enable-libwebp --enable-libxml2 \
  --enable-gnutls --enable-libbluray --enable-libssh \
  --enable-libpulse --enable-libjack --enable-alsa \
  --enable-sdl2 \
  --enable-libfreetype --enable-libfontconfig \
  --enable-libfribidi --enable-libharfbuzz \
  --enable-libbs2b --enable-libzmq --enable-libzimg \
  --enable-libsoxr --enable-libxvid \
  --enable-pic --enable-runtime-cpudetect \
  --extra-cflags="-O3 -fPIC" \
  --extra-ldflags="-Wl,-z,now -Wl,-z,relro"
```

**What doesn't work** (and why):

- `--enable-rkmpp` — no `/dev/mpp_service` on 7.0+ mainline.
- `--enable-libcdio` — the fork version is missing the dependency.
- `--enable-libsvtav1` — no `pkg-config` shim in the apt package.
- `--enable-libwavpack` — same.
- `--enable-libdrm --enable-libudev` — autodetect picks these up
  if the apt packages are installed; no need to pass explicitly.
- `--enable-v4l2-request` — wrong name. The fork has it built in;
  no flag needed. (Earlier pre-8.0 LibreELEC patches had a
  `--enable-v4l2-request` flag; that name is dead.)
- `--enable-glslang` + `--enable-libshaderc` — **mutually exclusive**.
  Pick one. libshaderc 2023.8.1 supports Vulkan 1.3, which is what
  mpv 0.41 needs. (For mpv 0.40 or earlier, glslang is fine.)

## The one-line patch

The fork's `libavfilter/vf_libplacebo.c:940` references
`PL_ALPHA_NONE`, which **was renamed to `PL_ALPHA_UNKNOWN` in
libplacebo 7.x**. The patch:

```bash
sed -i 's/PL_ALPHA_NONE/PL_ALPHA_UNKNOWN/' \
  libavfilter/vf_libplacebo.c
```

Without this, `make` fails with:

```text
libavfilter/vf_libplacebo.c:940:44: error: 'PL_ALPHA_NONE' undeclared
   (first use in this function); did you mean 'PL_LOG_NONE'?
```

**Do not** accept the compiler's "did you mean `PL_LOG_NONE`"
suggestion — it's a different macro entirely. See
[`libplacebo-api-drift`](libplacebo-api-drift) for the full
diagnosis.

## Why `apt-mark hold` matters

After `sudo make install`, you have two ffmpegs:

- `/usr/local/bin/ffmpeg` — your build, SONAME .62
- `/usr/bin/ffmpeg` — apt's 6.1.1, SONAME .60, **untouched**

The 6.1.1 ffmpeg is the one that `pipewire`, `qt6-multimedia`,
`kwin-wayland`, and `gstreamer1.0-libav` link against. If apt
ever upgrades it to 6.1.5 (patch level), the ABI of the .60
SONAME can change in ways that break the dependents.

The 8-package `apt-mark hold` is a 30-second action that
prevents that:

```bash
sudo apt-mark hold \
  ffmpeg libavcodec60 libavdevice60 libavfilter9 \
  libavformat60 libavutil58 libswresample4 libswscale7
```

Different SONAMEs (60 vs 62) means no conflict between the two
installations. The only thing that can go wrong is an apt patch-
level upgrade of 6.1.1 — the `apt-mark hold` prevents that.

## Verifying the build

```bash
# (See references/verify-detlev-ffmpeg-build.sh for the full version)
ffmpeg -version | head -1
# → ffmpeg version dfa10f6 Copyright (c) 2000-2025 the FFmpeg developers

ffmpeg -hide_banner -hwaccels 2>&1 | grep ^v4l2request
# → v4l2request

ldd $(which ffmpeg) | grep libavcodec
# → libavcodec.so.62 => /usr/local/lib/aarch64-linux-gnu/libavcodec.so.62
```

If all three return what you expect, the build is real.
For a real-hardware-decode end-to-end test, see [`verify`](verify).
