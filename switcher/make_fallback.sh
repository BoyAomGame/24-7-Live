#!/bin/sh
set -eu

SIZE="${VIDEO_SIZE:-1280x720}"
FPS="${FRAME_RATE:-30}"
GOP="$((FPS * ${GOP_SECONDS:-2}))"
AUDIO_RATE="${AUDIO_RATE:-48000}"

# A short MP4 is sufficient: MediaMTX loops it whenever /program has no publisher.
ffmpeg -y -hide_banner -loglevel warning \
  -f lavfi -i "smptebars=size=${SIZE}:rate=${FPS}" \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=${AUDIO_RATE}" \
  -t 10 -map 0:v:0 -map 1:a:0 \
  -c:v libx264 -preset "${X264_PRESET:-veryfast}" -profile:v high -pix_fmt yuv420p \
  -r "$FPS" -g "$GOP" -keyint_min "$GOP" -sc_threshold 0 \
  -b:v "${VIDEO_BITRATE:-4500k}" -maxrate "${VIDEO_MAXRATE:-4500k}" -bufsize "${VIDEO_BUFSIZE:-9000k}" \
  -c:a aac -b:a "${AUDIO_BITRATE:-160k}" -ar "$AUDIO_RATE" -ac "${AUDIO_CHANNELS:-2}" \
  -movflags +faststart /offline/bars.mp4
