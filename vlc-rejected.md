# VLC — rejected

> The "just use VLC" suggestion. Spoiler: it doesn't work on
> armbian noble, and even if it did, it wouldn't use the ffmpeg
> we built.

## The "obvious" alternative

VLC is the default Linux video player. It has built-in support
for `v4l2-request` (via the `avcodec-hw v4l2-request` module
since VLC 3.0.20). Why not just `apt install vlc` and call it a
day?

Three reasons.

## Reason 1: armbian noble ships VLC 3.0.20 without v4l2-request

The apt `vlc` package on noble 24.04 is `3.0.20-3build6`. Its
`vlc-plugin-base` package contains:

```bash
$ dpkg -L vlc-plugin-base | grep v4l2
/usr/lib/aarch64-linux-gnu/vlc/plugins/access/libv4l2_plugin.so
```

That `libv4l2_plugin.so` is the **input module** for V4L2
capture devices (webcams, capture cards). It is not the decoder
module. The decoder module — `libavcodec_plugin.so`'s
`v4l2_request` support — was not built into the noble package.

To verify: the upstream VLC `modules/codec/avcodec/avcodec.c`
file has a `v4l2_request` decoder module, but it's
`#ifdef HAVE_V4L2_REQUEST` in the upstream build. The noble
package was configured without it.

You can verify by:

```bash
$ vlc --list-modules 2>/dev/null | grep -iE "v4l2-request|avcodec-v4l2"
# (empty)
```

No v4l2-request decoder module. So even if you `apt install
vlc`, the `--avcodec-hw v4l2-request` flag is not going to
work; VLC will silently fall back to software decode and
the CPU will run hot.

## Reason 2: even with v4l2-request, VLC doesn't use our ffmpeg

VLC uses its own bundled `libavcodec` (a fork of FFmpeg from
VLC's own submodule pinning). The apt vlc package statically
links `libvlccore` and dynamically links `libavcodec.so.60`
(apt's ffmpeg 6.1.1) for the `avcodec` plugin.

If you `apt install vlc`, you get VLC → apt's libavcodec.so.60
→ no v4l2-request module. Our `libavcodec.so.62` (ffmpeg 8.0.1
in `/usr/local`) is **never loaded** by VLC. The 1.5h we spent
building the v4l2-request fork is wasted.

The dynamic linker trick that would force VLC to use our
ffmpeg (`LD_LIBRARY_PATH=/usr/local/lib/...`) doesn't work
either, because:

1. VLC expects `libavcodec.so.60` (specific SONAME). Our
   `libavcodec.so.62` is a different ABI — VLC's symbols
   reference `LIBAVCODEC_60` and would crash at link time
   against `.62`.
2. VLC's bundled modules also reference symbols from
   `libvlccore`, which doesn't load from `/usr/local`.

To get VLC with v4l2-request, you'd need to **rebuild
vlc-plugin-base from source** with `--enable-v4l2-request` in
its configure. That's another 1.5-2h compilation.

## Reason 3: the ffmpeg-based alternatives are better

- **ffplay** (built from our ffmpeg fork) uses our
  `v4l2request` hwaccel directly. 4K HEVC plays at 4-5x
  real-time.
- **mpv** would have been the gold standard, but the
  upstream/fork split is a mess (see [`mpv-rejected`](mpv-rejected)).
- **gstreamer** + v4l2sl elements already work on apt,
  no rebuild needed.

If you want a *real* GUI player experience and the mpv
rebuild is unacceptable, the right path is **GStreamer-based
players**:

- **Clapper** (GNOME) — uses gstreamer
- **Celluloid** (Xfce / MATE) — uses mpv
- **Haruna** (KDE) — uses mpv
- **Glide** (any) — uses mpv

Of these, Clapper is the only one that doesn't depend on
mpv. We haven't tested it; if you do, please update this
page.

## What we recommend instead

For a quick 4K HEVC decode-and-display:

```bash
ffplay -i 4k-hevc.mkv \
  -hwaccel v4l2request \
  -hwaccel_output_format drm_prime
```

This works. Speed is real. No GUI customization, but
functional. If you need OSD / playlist / scripting, the
next-best path is:

1. `apt install cellloid` (mpv frontend)
2. Re-add mpv using the LibreELEC `~ft/mpv` fork
   + jernejsk ffmpeg 7.1 (1.5h ffmpeg + 5 min mpv)
3. Accept losing the ext-SPS-RPS improvements

For documentation, this is all in
[`decision-log`](decision-log).
