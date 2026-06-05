# Install

> Step-by-step recipe. The 5 phases: preflight, apt deps, build
> ffmpeg, install ffmpeg, verify. Total wall time on RK3588S:
> about 2 hours (apt 5 min, ffmpeg build 25 min, libplacebo build
> 5 min, install 1 min, verify 1 min).

## Phase 0 — preflight

Verify the box is set up correctly *before* installing anything.

```bash
# 1. Kernel must be 7.0+ for ext-SPS-RPS
uname -r
# → 7.0.11-edge-rockchip64 (or any 7.x)

# 2. The rkvdec device must exist
ls -la /dev/video*
# → ... /dev/video1 ... (rkvdec2, video codec node)

# 3. CMA must be at least 512M for 4K HEVC
grep CmaTotal /proc/meminfo
# → CmaTotal: 524288 kB
# If it's 131072 kB (128M), edit /boot/armbianEnv.txt:
#   extraargs=cma=512M
# ... then reboot. (Don't reboot automatically — see
# system-modification-boundaries skill in our local config.)

# 4. apt ffmpeg 6.1.1 must be present (it provides libavcodec.so.60
#    for pipewire, kwin, qt6-multimedia)
dpkg -l ffmpeg libavcodec60 2>&1 | tail -3
# → ii  ffmpeg  7:6.1.1-3ubuntu5
# → ii  libavcodec60  7:6.1.1-3ubuntu5
```

If any of those checks fail, fix that first. The rest of the
install assumes a clean armbian noble box with the vendor
kde-plasma-desktop or gnome-shell installed.

## Phase 1 — apt dependencies

```bash
sudo apt update
sudo apt install -y \
  build-essential gcc g++ make pkg-config \
  git ca-certificates \
  nasm yasm \
  libx264-dev libx265-dev libvpx-dev libaom-dev libdav1d-dev \
  libfdk-aac-dev libmp3lame-dev libopus-dev libvorbis-dev \
  libtheora-dev libgsm1-dev libcodec2-dev libwavpack-dev \
  libsdl2-dev libpulse-dev libjack-dev libasound2-dev \
  libxcb1-dev libxext-dev libxrandr-dev libxinerama-dev \
  libxcursor-dev libxi-dev libxss-dev libxxf86vm-dev \
  libfreetype-dev libfontconfig1-dev libfribidi-dev libharfbuzz-dev \
  libbs2b-dev libzmq3-dev libzimg-dev libsoxr-dev libssh-dev \
  libbluray-dev libwebp-dev libxvidcore-dev libplacebo-dev \
  libshaderc-dev glslang-dev libarchive-dev zlib1g-dev
```

What we're NOT installing:

- `libcdio-dev` — not needed, also pulls a heavy dep chain.
- `libflite-dev` — not in noble pocket.
- `libsvtav1-dev` — has no pkg-config shim in noble.
- `libdrm-dev libudev-dev` — autodetected by ffmpeg, no
  need to pass explicitly.
- `mpv`, `vlc` — see [`mpv-rejected`](mpv-rejected) and
  [`vlc-rejected`](vlc-rejected).
- `linux-headers-7.0.11-edge-rockchip64` — we don't compile
  out-of-tree kernel modules. The rkvdec2 driver is in-tree.

## Phase 2 — build ffmpeg

```bash
mkdir -p ~/src
cd ~/src

# Clone Collabora detlev/ffmpeg, the v4l2-request-ext-sps-rps branch
git clone --depth=1 --branch=v4l2-request-ext-sps-rps-n8.0.1 \
  https://gitlab.collabora.com/detlev/ffmpeg.git detlev-ffmpeg

cd detlev-ffmpeg

# Verify HEAD
git log -1 --oneline
# → dfa10f6 wip: fix st rps

# Configure
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

`./configure` should print a summary ending with something
like `WARNING: ...` lines for v4l2 / libdrm autodetect and
then exit 0.

### The one-line patch

```bash
# Apply the libplacebo API drift fix
sed -i 's/PL_ALPHA_NONE/PL_ALPHA_UNKNOWN/' \
  libavfilter/vf_libplacebo.c
```

Without this, `make` fails on line 940 with
`PL_ALPHA_NONE undeclared`. See
[`libplacebo-api-drift`](libplacebo-api-drift) for the
full story.

### Build

```bash
# -j$(nproc) for parallel; 8 cores on RK3588S
make -j$(nproc) 2>&1 | tail -10
```

The build takes about 25 minutes on RK3588S. Watch the output
for any errors — common ones are:

- A missing dev package. Look for `error: 'X' not found` and
  install the corresponding `-dev` package.
- The libplacebo patch not applied. The error is
  `'PL_ALPHA_NONE' undeclared`.

## Phase 3 — install ffmpeg

```bash
# Install
sudo make install
sudo ldconfig

# Verify
which -a ffmpeg
# → /usr/local/bin/ffmpeg
# → /usr/bin/ffmpeg

ffmpeg -version | head -1
# → ffmpeg version dfa10f6 Copyright (c) 2000-2025 the FFmpeg developers

ldd /usr/local/bin/ffmpeg | grep libavcodec
# → libavcodec.so.62 => /usr/local/lib/aarch64-linux-gnu/libavcodec.so.62
```

### Hold the apt libs

The apt-installed ffmpeg 6.1.1 is still required by
`pipewire`, `qt6-multimedia`, and `kwin-wayland`. We don't
remove it; we hold it:

```bash
sudo apt-mark hold \
  ffmpeg libavcodec60 libavdevice60 libavfilter9 \
  libavformat60 libavutil58 libswresample4 libswscale7
```

The 8 packages will not be upgraded by `apt upgrade`. Their
SONAME is `.60`, which is different from our `.62`, so they
coexist without conflict.

## Phase 4 — verify

See [`verify`](verify) for the full procedure. The one-liner
that proves real hardware decode:

```bash
ffmpeg -v info -hwaccel v4l2request -hwaccel_output_format drm_prime \
  -i /tmp/vtest/test_4k_hevc.mp4 -f null -
```

Expected output:

```text
[AVHWFramesContext @ 0x...] Using V4L2 media driver rkvdec (7.0.11) for S265
Stream #0:0 -> #0:0 (hevc (native) -> wrapped_avframe (native))
frame=  60 ... speed=4.67x
```

If you see `Using V4L2 media driver rkvdec (7.0.11) for S265`,
the VPU is doing the work. If you see `hevc (software)` or no
such line, the build is broken. See
[`troubleshooting`](troubleshooting).

## Optional — install libplacebo 7.360.1

If you ever need to use `vo=gpu` in mpv (which requires
libplacebo `>= 7.360.1`), the apt `libplacebo338` (6.338.2) is
too old. Build upstream tag:

```bash
cd ~/src
git clone --depth=1 --branch=v7.360.1 \
  https://code.videolan.org/videolan/libplacebo.git
cd libplacebo
git submodule update --init --recursive
meson setup build --prefix=/usr/local
ninja -C build -j$(nproc)
sudo ninja -C build install
sudo ldconfig
```

About 5 minutes. The `v7.360.1` tag matches the meson version
in mpv 0.41. If you're not going to install mpv (we
recommend you don't), skip this phase.

## What you do NOT install

- **No mpv.** See [`mpv-rejected`](mpv-rejected).
- **No VLC.** See [`vlc-rejected`](vlc-rejected).
- **No kodi.** Would need the same `~ft/mpv` + jernejsk
  ffmpeg 7.1 stack to be useful.
- **No vendor mpp / librockchip-mpp.** Not needed on
  7.0+ mainline.
- **No `libreelec/ffmpeg`.** Older, less featureful, no
  ext-SPS-RPS.

## Total wall time

| Phase | Time |
|---|---|
| Phase 0 (preflight) | 30 sec |
| Phase 1 (apt) | 1.5 min |
| Phase 2 (ffmpeg configure + build) | 25 min |
| Phase 3 (install) | 1 min |
| Phase 4 (verify) | 1 min |
| Optional libplacebo 7 | 5 min |
| **Total** | **~30 min** (without mpv) or **~35 min** (with libplacebo 7) |

The optional libplacebo 7 build is only needed if you want
to attempt the `~ft/mpv` mpv 0.40 fork. We recommend skipping
it.
