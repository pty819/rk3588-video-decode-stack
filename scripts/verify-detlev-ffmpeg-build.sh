#!/usr/bin/env bash
# verify-detlev-ffmpeg-build.sh
# End-to-end smoke test for a Collabora detlev/ffmpeg build on RK3588 / 7.0+ mainline.
#
# Confirms:
#   1. The freshly-built ffmpeg has all 6 v4l2request decoders compiled in
#   2. The freshly-built ffmpeg has the v4l2request + vulkan hwaccels
#   3. LD_LIBRARY_PATH routes to the in-tree .so (not apt's libavcodec.so.60)
#   4. A 4K HEVC clip decodes via rkvdec (the S265 line, speed > 1x)
#   5. (Post-install) The installed /usr/local/bin/ffmpeg works without
#      LD_LIBRARY_PATH and the apt libav* packages are on hold.
#
# Exits 0 only if all checks pass.
#
# Usage:
#   ./scripts/verify-detlev-ffmpeg-build.sh
#   ./scripts/verify-detlev-ffmpeg-build.sh /path/to/ffmpeg/src

set -u

SRC="${1:-$HOME/src/detlev-ffmpeg/src}"
TESTCLIP="/tmp/vtest/test_4k_hevc.mp4"
TMPDIR="/tmp/detlev-verify-$$"
mkdir -p "$TMPDIR" /tmp/vtest
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0
note() { echo "[$1] $2"; }
ok()   { note " PASS" "$1"; PASS=$((PASS+1)); }
bad()  { note " FAIL" "$1"; FAIL=$((FAIL+1)); }

# Pre-flight: source dir
if [ ! -x "$SRC/ffmpeg" ]; then
    bad "ffmpeg binary not found at $SRC/ffmpeg"
    echo "       (Run this from inside the detlev-ffmpeg source dir, or pass it as argv 1.)"
    exit 2
fi

# Build LD_LIBRARY_PATH for the in-tree .so files
LDP="$SRC/libavutil:$SRC/libswscale:$SRC/libswresample:$SRC/libavcodec:$SRC/libavformat:$SRC/libavfilter:$SRC/libavdevice:$SRC/libpostproc"
export LD_LIBRARY_PATH="$LDP${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# 1. ldd sanity: should bind to the in-tree libavcodec.so.62, not apt's .60
note "----" "Check 1: in-tree .so binding"
LDCODEC=$(LD_LIBRARY_PATH="$LDP" ldd "$SRC/ffmpeg" 2>/dev/null | grep libavcodec | awk '{print $3}' | head -1)
if echo "$LDCODEC" | grep -q "libavcodec\.so\.62"; then
    ok "ffmpeg binds to in-tree libavcodec.so.62: $LDCODEC"
elif echo "$LDCODEC" | grep -q "libavcodec\.so\.60"; then
    bad "ffmpeg is binding to APT's libavcodec.so.60 — LD_LIBRARY_PATH isn't taking effect"
    bad "  Set explicitly: export LD_LIBRARY_PATH=\"$LDP:\$LD_LIBRARY_PATH\""
else
    bad "unexpected libavcodec binding: $LDCODEC"
fi

# 2. -hwaccels: must show v4l2request
note "----" "Check 2: v4l2request hwaccel compiled in (Collabora path: hwaccel layer, not a new decoder)"
# In Collabora detlev/ffmpeg, v4l2request is exposed ONLY as a hwaccel, not as a separate
# decoder class. The v4l2m2m decoders (h264_v4l2m2m, hevc_v4l2m2m, etc.) get their request-
# API path activated by -hwaccel v4l2request. So check hwaccels, not -decoders.
HWACCELS=$(LD_LIBRARY_PATH="$LDP" "$SRC/ffmpeg" -hide_banner -hwaccels 2>/dev/null)
if echo "$HWACCELS" | grep -qE "^v4l2request"; then
    ok "v4l2request hwaccel present (this is the Collabora detlev/ffmpeg 8.0.1 path)"
else
    bad "v4l2request hwaccel missing — ffmpeg will fall back to stateful v4l2m2m"
fi
# Sanity: the v4l2m2m decoders must also exist (the actual codec wrappers)
M2M_COUNT=$(LD_LIBRARY_PATH="$LDP" "$SRC/ffmpeg" -hide_banner -decoders 2>/dev/null \
    | grep -cE "_(v4l2m2m) +V4L2")
if [ "$M2M_COUNT" -ge 6 ]; then
    ok "$M2M_COUNT v4l2m2m decoders present (h264/hevc/mpeg2/vp8/vp9/+; the v4l2request hwaccel rides on these)"
else
    bad "only $M2M_COUNT v4l2m2m decoders — too few codec wrappers compiled in"
fi

# 3. -hwaccels: must show v4l2request + vulkan
note "----" "Check 3: v4l2request + vulkan hwaccels"
HWACCELS=$(LD_LIBRARY_PATH="$LDP" "$SRC/ffmpeg" -hide_banner -hwaccels 2>/dev/null)
echo "$HWACCELS" | grep -q "^v4l2request" && ok "v4l2request hwaccel present" \
    || bad "v4l2request hwaccel missing"
echo "$HWACCELS" | grep -q "^vulkan" && ok "vulkan hwaccel present" \
    || bad "vulkan hwaccel missing (libplacebo / libshaderc may not be linked)"

# 4. Generate test clip (only if missing)
note "----" "Check 4: 4K HEVC decode test"
if [ ! -f "$TESTCLIP" ]; then
    note " INFO" "generating $TESTCLIP (3-second 4K HEVC, software-encoded)..."
    LD_LIBRARY_PATH="$LDP" "$SRC/ffmpeg" -y -hide_banner -loglevel error \
        -f lavfi -i "testsrc2=size=3840x2160:rate=30:duration=3" \
        -c:v libx265 -preset ultrafast -pix_fmt yuv420p \
        "$TESTCLIP" 2>&1 | tail -3
fi
[ -f "$TESTCLIP" ] || { bad "could not create $TESTCLIP"; exit 1; }

# Run the actual decode
LOG="$TMPDIR/decode.log"
LD_LIBRARY_PATH="$LDP" "$SRC/ffmpeg" -v info -hwaccel v4l2request \
    -hwaccel_output_format drm_prime \
    -i "$TESTCLIP" -f null - 2>"$LOG" 1>/dev/null
RC=$?

# 4a. S265 line proves rkvdec matched
if grep -q "Using V4L2 media driver rkvdec.*for S265" "$LOG"; then
    ok "rkvdec matched as S265 driver — real hardware decode path"
else
    bad "no 'rkvdec ... for S265' line in decode log"
    echo "       Full log tail:"
    tail -20 "$LOG" | sed 's/^/         /'
fi

# 4b. Stream mapping should show hevc (native) decoder + wrapped_avframe output
# (the v4l2request path uses the stock hevc decoder, not a hevc_v4l2request decoder name)
if grep -qE "Stream #0:0 -> #0:0 \(hevc \(native\) -> wrapped_avframe \(native\)\)" "$LOG"; then
    ok "Stream mapping: hevc (native) -> wrapped_avframe (Collabora v4l2request hwaccel path)"
else
    bad "Stream mapping is not the expected v4l2request pattern"
    grep -E "Stream mapping:|hevc " "$LOG" | sed 's/^/         /'
fi
# Sanity: the actual decoder must NOT be 'hevc (software)' (that means soft fallback)
if grep -qE "hevc \(software\)" "$LOG"; then
    bad "decoder is hevc (software) — silent soft fallback, no VPU"
fi

# 4c. speed >= 1x — real VPU work
SPEED=$(grep -oE "speed= *[0-9.]+x" "$LOG" | tail -1 | grep -oE "[0-9.]+")
if [ -n "$SPEED" ] && awk "BEGIN{exit !($SPEED >= 1.0)}"; then
    ok "decode speed = ${SPEED}x (>= 1x = realtime or faster, real VPU)"
else
    bad "decode speed = ${SPEED:-?}x (software HEVC on RK3588S tops out ~0.3-0.5x)"
fi

# Summary
echo
echo "=========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "=========================================="

# 5. Post-install check (only if /usr/local/bin/ffmpeg exists)
if [ -x /usr/local/bin/ffmpeg ]; then
    echo
    note "----" "Check 5: post-install /usr/local/bin/ffmpeg works without LD_LIBRARY_PATH"
    INSTALLED_PATH=$(which -a ffmpeg 2>/dev/null | head -1)
    if [ "$INSTALLED_PATH" = "/usr/local/bin/ffmpeg" ]; then
        ok "which ffmpeg → /usr/local/bin/ffmpeg (installed binary wins PATH)"
    else
        bad "which ffmpeg → $INSTALLED_PATH (expected /usr/local/bin/ffmpeg)"
    fi

    INSTALLED_VER=$(/usr/local/bin/ffmpeg -version 2>/dev/null | head -1)
    echo "$INSTALLED_VER" | grep -q "dfa10f6" \
        && ok "installed ffmpeg reports HEAD dfa10f6 (Collabora detlev/ffmpeg 8.0.1)" \
        || bad "installed ffmpeg version unexpected: $INSTALLED_VER"

    if [ -f /usr/local/lib/aarch64-linux-gnu/libavcodec.so.62 ]; then
        ok "libavcodec.so.62 installed at /usr/local/lib/aarch64-linux-gnu/"
    else
        bad "libavcodec.so.62 missing from /usr/local/lib"
    fi

    if [ -f /usr/lib/aarch64-linux-gnu/libavcodec.so.60 ] && [ ! -L /usr/lib/aarch64-linux-gnu/libavcodec.so ]; then
        ok "apt libavcodec.so.60 untouched (SONAME .60 != .62, no conflict)"
    else
        bad "apt libavcodec.so.60 missing or symlinked away"
    fi

    HOLD_COUNT=$(apt-mark showhold 2>/dev/null | grep -cE "^(ffmpeg|libav(codec|device|filter|format|util)60?|libsw(r|scale|resample)[0-9]+)$")
    if [ "$HOLD_COUNT" -ge 1 ]; then
        ok "$HOLD_COUNT apt ffmpeg-related packages on hold (defensive)"
    else
        bad "no apt ffmpeg packages on hold (D step not executed?)"
    fi

    # 5a. Real rkvdec decode using the installed binary (no LD_LIBRARY_PATH)
    if [ -f "$TESTCLIP" ]; then
        LOG="$TMPDIR/decode-installed.log"
        /usr/local/bin/ffmpeg -v info -hwaccel v4l2request \
            -hwaccel_output_format drm_prime \
            -i "$TESTCLIP" -f null - 2>"$LOG" 1>/dev/null
        if grep -q "Using V4L2 media driver rkvdec.*for S265" "$LOG"; then
            ok "installed /usr/local/bin/ffmpeg decodes 4K HEVC via rkvdec (no LD_LIBRARY_PATH needed)"
        else
            bad "installed ffmpeg decode did not match rkvdec path"
            tail -10 "$LOG" | sed 's/^/         /'
        fi
    fi
fi

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
