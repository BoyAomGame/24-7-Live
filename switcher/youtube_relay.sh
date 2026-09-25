#!/bin/sh
set -eu

PROGRAM_URL="${PROGRAM_URL:-rtmp://mediamtx:1935/program}"
YOUTUBE_RTMP_URL="${YOUTUBE_RTMP_URL:-rtmps://a.rtmps.youtube.com/live2}"
YOUTUBE_STREAM_KEY="${YOUTUBE_STREAM_KEY:-}"
RECONNECT_SECONDS="${YOUTUBE_RECONNECT_SECONDS:-5}"

if [ -z "$YOUTUBE_STREAM_KEY" ]; then
  echo "YOUTUBE_STREAM_KEY is required to relay the program feed to YouTube" >&2
  exit 1
fi

destination="${YOUTUBE_RTMP_URL%/}/${YOUTUBE_STREAM_KEY}"

trap 'exit 0' INT TERM

while true; do
  echo "Starting YouTube relay from ${PROGRAM_URL}"
  # The program feed is already fixed to YouTube-compatible H.264/AAC settings.
  # Stream-copying avoids a second encode and keeps the end-to-end delay low.
  ffmpeg -hide_banner -loglevel warning -rw_timeout 5000000 -i "$PROGRAM_URL" \
    -map 0:v:0 -map 0:a:0 -c copy \
    -flvflags no_duration_filesize -f flv "$destination" || true

  echo "YouTube relay disconnected; retrying in ${RECONNECT_SECONDS}s"
  sleep "$RECONNECT_SECONDS"
done
