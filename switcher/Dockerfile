FROM jrottenberg/ffmpeg:8-alpine

COPY switcher.sh make_fallback.sh youtube_relay.sh playlist_player.sh /app/
ENTRYPOINT ["sh", "/app/switcher.sh"]
