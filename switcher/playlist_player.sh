#!/bin/sh
set -eu

MEDIA_DIR="${MEDIA_DIR:-/media/videos}"
PLAYLIST_FILE="${PLAYLIST_FILE:-/media/playlist.txt}"
OUTPUT_URL="${OUTPUT_URL:-rtmp://mediamtx:1935/media}"
SIZE="${VIDEO_SIZE:-1280x720}"
SIZE_COLON="$(printf '%s' "$SIZE" | tr 'x' ':')"
FPS="${FRAME_RATE:-30}"
GOP="$((FPS * ${GOP_SECONDS:-2}))"

play_file() {
  file="$1"
  path="$MEDIA_DIR/$file"
  [ -f "$path" ] || return 0
  echo "Playing $file"
  audio_track="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 "$path" 2>/dev/null || true)"
  if [ "$audio_track" = "audio" ]; then
    ffmpeg -hide_banner -loglevel warning -re -i "$path" \
      -vf "scale=${SIZE}:force_original_aspect_ratio=decrease,pad=${SIZE_COLON}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1" \
      -map 0:v:0 -map 0:a:0 -c:v libx264 -preset "${X264_PRESET:-veryfast}" -profile:v high -pix_fmt yuv420p \
      -r "$FPS" -g "$GOP" -keyint_min "$GOP" -sc_threshold 0 -b:v "${VIDEO_BITRATE:-4500k}" -maxrate "${VIDEO_MAXRATE:-4500k}" -bufsize "${VIDEO_BUFSIZE:-9000k}" \
      -c:a aac -b:a "${AUDIO_BITRATE:-160k}" -ar "${AUDIO_RATE:-48000}" -ac "${AUDIO_CHANNELS:-2}" -f flv "$OUTPUT_URL" || true
  else
    ffmpeg -hide_banner -loglevel warning -re -i "$path" -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=${AUDIO_RATE:-48000}" \
      -vf "scale=${SIZE}:force_original_aspect_ratio=decrease,pad=${SIZE_COLON}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1" \
      -map 0:v:0 -map 1:a:0 -c:v libx264 -preset "${X264_PRESET:-veryfast}" -profile:v high -pix_fmt yuv420p \
      -r "$FPS" -g "$GOP" -keyint_min "$GOP" -sc_threshold 0 -b:v "${VIDEO_BITRATE:-4500k}" -maxrate "${VIDEO_MAXRATE:-4500k}" -bufsize "${VIDEO_BUFSIZE:-9000k}" \
      -c:a aac -b:a "${AUDIO_BITRATE:-160k}" -ar "${AUDIO_RATE:-48000}" -ac "${AUDIO_CHANNELS:-2}" -f flv "$OUTPUT_URL" || true
  fi
}

mkdir -p "$MEDIA_DIR"
while true; do
  if [ ! -s "$PLAYLIST_FILE" ]; then sleep 3; continue; fi
  while IFS= read -r file || [ -n "$file" ]; do play_file "$file"; done < "$PLAYLIST_FILE"
done
