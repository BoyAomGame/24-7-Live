#!/bin/sh
set -eu

MEDIA_DIR="${MEDIA_DIR:-/media/videos}"
PLAYLIST_FILE="${PLAYLIST_FILE:-/media/playlist.txt}"
PLAYBACK_FLAG="${PLAYBACK_FLAG:-/media/playback.enabled}"
PLAYLIST_MODE_FILE="${PLAYLIST_MODE_FILE:-/media/playlist.mode}"
OUTPUT_URL="${OUTPUT_URL:-rtmp://mediamtx:1935/media}"
API_URL="${MTX_API_URL:-http://mediamtx:9997}"
SIZE="${VIDEO_SIZE:-1280x720}"
SIZE_COLON="$(printf '%s' "$SIZE" | tr 'x' ':')"
FPS="${FRAME_RATE:-30}"
GOP="$((FPS * ${GOP_SECONDS:-2}))"
player_pid=""

stop_player() {
  if [ -n "$player_pid" ] && kill -0 "$player_pid" 2>/dev/null; then
    kill "$player_pid"
    wait "$player_pid" 2>/dev/null || true
  fi
  player_pid=""
}

trap 'stop_player; exit 0' INT TERM

has_reader() {
  status="$(wget -qO- "${API_URL}/v3/paths/get/media" 2>/dev/null || true)"
  printf '%s' "$status" | grep -Eq '"readers":[[:space:]]*\[[[:space:]]*\{'
}

wait_for_reader() {
  while ! has_reader; do
    if [ "$(cat "$PLAYBACK_FLAG" 2>/dev/null || echo on)" != "on" ]; then return 1; fi
    sleep 1
  done
  # A second check rules out the switcher's short metadata probe.
  sleep 1
  [ "$(cat "$PLAYBACK_FLAG" 2>/dev/null || echo on)" = "on" ] && has_reader
}

play_file() {
  file="$1"
  case "$file" in
    http://*|https://*) path="$file" ;;
    *) path="$MEDIA_DIR/$file"; [ -f "$path" ] || return 0 ;;
  esac
  echo "Playing $file"
  audio_track="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 "$path" 2>/dev/null || true)"
  if [ "$audio_track" = "audio" ]; then
    ffmpeg -hide_banner -loglevel warning -re -i "$path" \
      -vf "scale=${SIZE}:force_original_aspect_ratio=decrease,pad=${SIZE_COLON}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1" \
      -map 0:v:0 -map 0:a:0 -c:v libx264 -preset "${X264_PRESET:-veryfast}" -profile:v high -pix_fmt yuv420p \
      -r "$FPS" -g "$GOP" -keyint_min "$GOP" -sc_threshold 0 -b:v "${VIDEO_BITRATE:-4500k}" -maxrate "${VIDEO_MAXRATE:-4500k}" -bufsize "${VIDEO_BUFSIZE:-9000k}" \
      -c:a aac -b:a "${AUDIO_BITRATE:-160k}" -ar "${AUDIO_RATE:-48000}" -ac "${AUDIO_CHANNELS:-2}" -flvflags no_duration_filesize -f flv "$OUTPUT_URL" &
  else
    ffmpeg -hide_banner -loglevel warning -re -i "$path" -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=${AUDIO_RATE:-48000}" \
      -vf "scale=${SIZE}:force_original_aspect_ratio=decrease,pad=${SIZE_COLON}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1" \
      -map 0:v:0 -map 1:a:0 -c:v libx264 -preset "${X264_PRESET:-veryfast}" -profile:v high -pix_fmt yuv420p \
      -r "$FPS" -g "$GOP" -keyint_min "$GOP" -sc_threshold 0 -b:v "${VIDEO_BITRATE:-4500k}" -maxrate "${VIDEO_MAXRATE:-4500k}" -bufsize "${VIDEO_BUFSIZE:-9000k}" \
      -c:a aac -b:a "${AUDIO_BITRATE:-160k}" -ar "${AUDIO_RATE:-48000}" -ac "${AUDIO_CHANNELS:-2}" -shortest -flvflags no_duration_filesize -f flv "$OUTPUT_URL" &
  fi
  player_pid=$!
  missed_readers=0
  while kill -0 "$player_pid" 2>/dev/null; do
    sleep 1
    if has_reader; then
      missed_readers=0
    else
      missed_readers=$((missed_readers + 1))
      if [ "$missed_readers" -ge 2 ]; then
        echo "Program stopped reading media; keeping $file in the playlist"
        stop_player
        return 1
      fi
    fi
  done
  if wait "$player_pid"; then
    player_pid=""
    return 0
  fi
  player_pid=""
  echo "Playback failed for $file; keeping it in the playlist" >&2
  return 1
}

mkdir -p "$MEDIA_DIR"
while true; do
  if [ "$(cat "$PLAYBACK_FLAG" 2>/dev/null || echo on)" != "on" ] || [ ! -s "$PLAYLIST_FILE" ]; then sleep 1; continue; fi
  if [ "$(cat "$PLAYLIST_MODE_FILE" 2>/dev/null || echo loop)" = "once" ]; then
    file="$(sed -n '1p' "$PLAYLIST_FILE")"
    if wait_for_reader && play_file "$file"; then
      # A dashboard edit may have changed the queue during playback.
      if [ "$(sed -n '1p' "$PLAYLIST_FILE")" = "$file" ]; then
        temporary="${PLAYLIST_FILE}.tmp"
        sed '1d' "$PLAYLIST_FILE" > "$temporary"
        mv "$temporary" "$PLAYLIST_FILE"
      fi
    else
      sleep 2
    fi
  else
    while IFS= read -r file || [ -n "$file" ]; do
      if ! wait_for_reader; then break; fi
      if ! play_file "$file"; then sleep 2; break; fi
    done < "$PLAYLIST_FILE"
  fi
done
