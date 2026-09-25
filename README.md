# Always-on RTMP output with RTMP/SRT input and bars fallback

This stack accepts one live input and permanently publishes a `program` RTMP
path. It shows a looping SMPTE colour-bar clip with silent stereo AAC whenever
the input is not present. When an input appears it becomes the program
automatically.

The important part is the codec contract: the bar clip and live input are
encoded with the same fixed settings. MediaMTX then switches between them
internally, without re-encoding and without disconnecting RTMP readers. This
avoids needing the incoming encoder to match the fallback file's codec, rate,
or audio layout.

## Start

1. Install Docker Desktop and start it.
2. From this folder, run `docker compose up --build -d`.
3. Read the always-available output at:

   `rtmp://YOUR_SERVER_IP:1935/program`

At first this is bars. The first startup can take a few seconds while Docker
builds the bar clip and starts the services.

## Send a live input

Use either of the following URLs. They both feed the same `incoming` path.

| Protocol | Publish URL |
| --- | --- |
| RTMP | `rtmp://YOUR_SERVER_IP:1935/incoming` |
| SRT caller | `srt://YOUR_SERVER_IP:8890?streamid=publish:incoming&pkt_size=1316` |

For example, replace the FFmpeg input below with a camera, file, or capture
device:

```text
ffmpeg -re -i INPUT -c copy -f flv rtmp://YOUR_SERVER_IP:1935/incoming
```

SRT normally carries MPEG-TS. A matching test sender is:

```text
ffmpeg -re -i INPUT -c copy -f mpegts "srt://YOUR_SERVER_IP:8890?streamid=publish:incoming&pkt_size=1316"
```

The live source must contain H.264-compatible video. Its original video size,
frame rate, bitrate, sample rate, and channel layout do not need to match the
program—this stack normalizes them. Video-only sources receive generated
silent stereo AAC so the program still has exactly two audio channels.

## Program format

Defaults live in `.env` and are deliberately shared by bars and live:

| Track | Default |
| --- | --- |
| Video | H.264 High, 1280×720, 30 fps, 4.5 Mb/s CBR-style VBV, 2-second GOP, yuv420p |
| Audio | AAC-LC, 48 kHz, stereo, 160 kb/s |

Change `.env` and restart the stack to use another format. Keep the settings
fixed while it is on air; changing them requires a final-encoder restart.

## Stream the program to YouTube

The optional YouTube relay republishes the same always-on `program` feed to
YouTube. It stream-copies the existing H.264/AAC output, so it does not add a
second video encode or change local RTMP playback.

1. In YouTube Studio, select **Create** > **Go live**, create or choose a
   stream, and copy its server URL and stream key.
2. In `.env`, set `YOUTUBE_RTMP_URL` to that server URL and set
   `YOUTUBE_STREAM_KEY` to the private key. Do not put the key in
   `.env.example` or commit it to Git.
3. Start the normal stack and relay together:

   ```text
   docker compose --profile youtube up --build -d
   ```

   The relay automatically reconnects when YouTube or the local program feed
   disconnects. To stop only the YouTube relay, run:

   ```text
   docker compose --profile youtube stop youtube-relay
   ```

YouTube must have live streaming enabled. First-time activation can take up to
24 hours. In YouTube's Live Control Room, use the stream preview and go live
when it is ready.

## Playlist playback

Start the media profile with `docker compose --profile media up -d --build`.
Upload videos or add direct MP4/HLS links in the media dashboard and save the
playlist. The switcher connects to the media path before the player starts a
clip, so its opening is included in the program output. The media path fills
the short gaps between clips with color bars without disconnecting its reader.
Already normalized playlist video is copied into `program` rather than
encoded a second time.

Local uploads are prepared once under `media/normalized/`, then played by
stream copy. The first play can take time to prepare on a small VPS; color bars
remain on screen until the file is ready. Allow disk space for the prepared
copy alongside the original upload. Replacing or deleting an upload removes
its prepared copy.

When live input becomes active, playback stops and the current playlist item
stays queued. Once live input ends, that item starts again from the beginning.
In **Play once then remove** mode, an item is removed only after it finishes
successfully; the uploaded file itself is retained.

## Source recordings

Every received stream is recorded before it is normalized, so a recording
keeps the source's original codecs and audio layout. Files are written under
`recordings/incoming/` beside this project. They are fragmented MP4 recordings,
split hourly (or when the input disconnects), and are retained until you remove
them. Monitor disk space; recording has no automatic retention limit.

## Important operational notes

- RTMP readers remain connected during an input switch. The live normalizer
  starts only after two healthy checks and begins at a keyframe, so the bars
  will remain visible until live video is ready.
- This is an open LAN example. Do not expose ports 1935/8890 directly to the
  internet without firewall rules and MediaMTX authentication.

## Check and stop

```text
docker compose logs -f switcher
docker compose down
```

MediaMTX accepts RTMP and SRT publishing and exposes the input path through
its control API; the switcher uses that API only for presence detection. See
the official MediaMTX documentation for protocol and authentication details:
https://mediamtx.org/docs/publish/srt-clients
