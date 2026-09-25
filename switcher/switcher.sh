#!/bin/sh
set -eu

SIZE="${VIDEO_SIZE:-1280x720}"
SIZE_COLON="$(printf '%s' "$SIZE" | tr 'x' ':')"
FPS="${FRAME_RATE:-30}"
GOP="$((FPS * ${GOP_SECONDS:-2}))"
INPUT_URL="${INPUT_URL:-rtmp://mediamtx:1935/incoming}"
MEDIA_URL="${MEDIA_URL:-rtmp://mediamtx:1935/media}"
OUTPUT_URL="${OUTPUT_URL:-rtmp://mediamtx:1935/program}"
API_URL="${MTX_API_URL:-http://mediamtx:9997}"
CHECK_INTERVAL="${CHECK_INTERVAL_SECONDS:-2}"
LIVE_CONFIRMATIONS="${LIVE_CONFIRMATIONS:-2}"
worker_pid=""
ready_checks=0
active_source=""
PLAYLIST_FILE="${PLAYLIST_FILE:-/media/playlist.txt}"
PLAYBACK_FLAG="${PLAYBACK_FLAG:-/media/playback.enabled}"

stop_worker() {
  if [ -n "$worker_pid" ] && kill -0 "$worker_pid" 2>/dev/null; then
    echo "Stopping program source"
    kill "$worker_pid"
    wait "$worker_pid" 2>/dev/null || true
  fi
  worker_pid=""
}

trap 'stop_worker; exit 0' INT TERM

source_has_audio() {
  source_url="$1"
  audio_track="$(ffprobe -v error -rw_timeout 3000000 -select_streams a:0 \
    -show_entries stream=codec_type -of csv=p=0 "$source_url" 2>/dev/null || true)"
  [ "$audio_track" = "audio" ]
}

start_live() {
  source_url="$1"
  echo "Starting live input normalizer"
  video_filter="scale=${SIZE}:force_original_aspect_ratio=decrease,pad=${SIZE_COLON}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1"
  if source_has_audio "$source_url"; then
    ffmpeg -hide_banner -loglevel warning -rw_timeout 5000000 -i "$source_url" \
      -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=${AUDIO_RATE:-48000}" \
      -filter_complex "[0:v:0]${video_filter}[video];[0:a:0]aresample=async=1:first_pts=0[audio]" \
      -map "[video]" -map "[audio]" \
      -c:v libx264 -preset "${X264_PRESET:-veryfast}" -profile:v high -pix_fmt yuv420p \
      -r "$FPS" -g "$GOP" -keyint_min "$GOP" -sc_threshold 0 \
      -b:v "${VIDEO_BITRATE:-4500k}" -maxrate "${VIDEO_MAXRATE:-4500k}" -bufsize "${VIDEO_BUFSIZE:-9000k}" \
      -c:a aac -b:a "${AUDIO_BITRATE:-160k}" -ar "${AUDIO_RATE:-48000}" -ac "${AUDIO_CHANNELS:-2}" \
      -flvflags no_duration_filesize -f flv "$OUTPUT_URL" &
  else
    echo "Live input has no readable audio; adding silent stereo AAC"
    ffmpeg -hide_banner -loglevel warning -rw_timeout 5000000 -i "$source_url" \
      -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=${AUDIO_RATE:-48000}" \
      -vf "$video_filter" -map 0:v:0 -map 1:a:0 \
      -c:v libx264 -preset "${X264_PRESET:-veryfast}" -profile:v high -pix_fmt yuv420p \
      -r "$FPS" -g "$GOP" -keyint_min "$GOP" -sc_threshold 0 \
      -b:v "${VIDEO_BITRATE:-4500k}" -maxrate "${VIDEO_MAXRATE:-4500k}" -bufsize "${VIDEO_BUFSIZE:-9000k}" \
      -c:a aac -b:a "${AUDIO_BITRATE:-160k}" -ar "${AUDIO_RATE:-48000}" -ac "${AUDIO_CHANNELS:-2}" \
      -flvflags no_duration_filesize -f flv "$OUTPUT_URL" &
  fi
  worker_pid=$!
}

start_media() {
  echo "Connecting playlist media to program"
  # The player and the media fallback already use the program codec contract.
  # Stream copy avoids a second encode and keeps this RTMP reader connected.
  ffmpeg -hide_banner -loglevel warning -rw_timeout 5000000 -i "$MEDIA_URL" \
    -map 0:v:0 -map 0:a:0 -c copy \
    -flvflags no_duration_filesize -f flv "$OUTPUT_URL" &
  worker_pid=$!
}

start_source() {
  if [ "$active_source" = "$MEDIA_URL" ]; then
    start_media
  else
    start_live "$active_source"
  fi
}

while true; do
  # A path-specific API call avoids brittle parsing of the complete paths list.
  status="$(wget -qO- "${API_URL}/v3/paths/get/incoming" 2>/dev/null || true)"
  case "$status" in
    *'"ready":true'*) ready_checks=$((ready_checks + 1)) ;;
    *) ready_checks=0 ;;
  esac
  [ "$ready_checks" -gt "$LIVE_CONFIRMATIONS" ] && ready_checks="$LIVE_CONFIRMATIONS"

  next_source=""
  if [ "$ready_checks" -ge "$LIVE_CONFIRMATIONS" ]; then next_source="$INPUT_URL";
  elif [ "$(cat "$PLAYBACK_FLAG" 2>/dev/null || echo on)" = "on" ] && [ -s "$PLAYLIST_FILE" ]; then next_source="$MEDIA_URL"; fi

  if [ "$next_source" != "$active_source" ]; then
    stop_worker
    active_source="$next_source"
    [ -n "$active_source" ] && start_source
  elif [ -n "$active_source" ] && { [ -z "$worker_pid" ] || ! kill -0 "$worker_pid" 2>/dev/null; }; then
    worker_pid=""
    start_source
  fi
  sleep "$CHECK_INTERVAL"
done
