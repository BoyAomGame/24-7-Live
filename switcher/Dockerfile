FROM jrottenberg/ffmpeg:8-alpine

RUN apk add --no-cache font-dejavu tzdata

COPY switcher.sh make_fallback.sh youtube_relay.sh playlist_player.sh /app/
ENTRYPOINT ["sh", "/app/switcher.sh"]
