# RK3588 Video Decode Stack

A reproducible recipe to get **real 4K HEVC hardware decode** on a
Rockchip RK3588 / RK3588S running mainline Linux kernel 7.0+,
built around the upstream `v4l2-request` (stateless) decoder API
and `rkvdec2` (VDPU381) hardware.

The full Sphinx-rendered site is at
[https://pty819.github.io/rk3588-video-decode-stack/](https://pty819.github.io/rk3588-video-decode-stack/).

## TL;DR

```bash
# 1. apt deps
sudo apt install -y build-essential gcc g++ make pkg-config \
  git ca-certificates nasm yasm \
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

# 2. clone + patch
git clone --depth=1 --branch=v4l2-request-ext-sps-rps-n8.0.1 \
  https://gitlab.collabora.com/detlev/ffmpeg.git
cd ffmpeg
sed -i 's/PL_ALPHA_NONE/PL_ALPHA_UNKNOWN/' libavfilter/vf_libplacebo.c

# 3. configure + build
./configure --prefix=/usr/local \
  --libdir=/usr/local/lib/aarch64-linux-gnu \
  --shlibdir=/usr/local/lib/aarch64-linux-gnu \
  --enable-shared --disable-static \
  --enable-gpl --enable-version3 --enable-nonfree \
  --enable-libplacebo --enable-libshaderc \
  --enable-libx264 --enable-libx265 --enable-libvpx --enable-libaom \
  --enable-libdav1d --enable-libfdk-aac --enable-libmp3lame \
  --enable-libopus --enable-libvorbis --enable-libtheora \
  --enable-libcodec2 --enable-libwebp --enable-libxml2 \
  --enable-gnutls --enable-libbluray --enable-libssh \
  --enable-libpulse --enable-libjack --enable-alsa \
  --enable-sdl2 --enable-libfreetype --enable-libfontconfig \
  --enable-libfribidi --enable-libharfbuzz \
  --enable-libbs2b --enable-libzmq --enable-libzimg \
  --enable-libsoxr --enable-libxvid \
  --enable-pic --enable-runtime-cpudetect \
  --extra-cflags="-O3 -fPIC" \
  --extra-ldflags="-Wl,-z,now -Wl,-z,relro"

make -j$(nproc)
sudo make install
sudo ldconfig

# 4. hold the apt libs
sudo apt-mark hold ffmpeg libavcodec60 libavdevice60 libavfilter9 \
  libavformat60 libavutil58 libswresample4 libswscale7

# 5. verify
ffmpeg -v info -hwaccel v4l2request -hwaccel_output_format drm_prime \
  -i /tmp/test_4k_hevc.mp4 -f null -
# Look for: "Using V4L2 media driver rkvdec (7.0.11) for S265"
#           "speed=4.6x" or higher
```

Total wall time: about 30 minutes on RK3588S.

## What this is

- **A working ffmpeg 8.0.1** with the Collabora v4l2-request
  hwaccel, installed in `/usr/local`, coexisting with the apt
  ffmpeg 6.1.1.
- **A gstreamer pipeline** that already works on apt for 4K
  HEVC, no rebuild needed.
- **A documented list of what doesn't work**: mpv, VLC, and
  the reasons they were rejected.

## What this isn't

- A solution to every 4K video problem. See the HEVC ST RPS
  wip bug in [`docs/known-bugs.md`](docs/known-bugs.md).
- A GUI player. Use `ffplay` (built from the same ffmpeg) or
  gstreamer-based players like Clapper.
- A Linux distribution. It's a recipe for armbian noble 24.04.

## Repository layout

```
.
├── conf.py                            # Sphinx config
├── index.md                           # Site homepage
├── motivation.md                      # Why this stack exists
├── hardware.md                        # What kernel/driver/UAPI
├── glossary.md                        # S264/S265, RPS, CMA, etc.
├── ffmpeg-v4l2request.md              # The Collabora fork
├── gstreamer-v4l2sl.md                # gstreamer's v4l2sl
├── mpv-rejected.md                    # Three mpv attempts
├── vlc-rejected.md                    # Why apt VLC doesn't work
├── install.md                         # 5-phase install recipe
├── verify.md                          # What "working" looks like
├── troubleshooting.md                 # Common failure modes
├── known-bugs.md                      # HEVC ST RPS, etc.
├── decision-log.md                    # Time-ordered decisions
├── verify-scripts.md                  # The .sh scripts
├── libplacebo-api-drift.md            # The PL_ALPHA_NONE patch
├── requirements.txt                   # Sphinx deps
├── Makefile                           # sphinx-build wrapper
├── .github/workflows/docs.yml         # GitHub Pages deploy
├── LICENSE                            # MIT
└── README.md                          # This file
```

## Building the docs locally

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
make html
# Open _build/html/index.html
```

## License

MIT. See [`LICENSE`](LICENSE).
