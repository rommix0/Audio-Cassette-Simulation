#!/bin/bash

# Enforce strict error handling
set -e

# Default to primary relay if no argument is provided
STREAM_URL="${1:-http://ice6.somafm.com/dronezone-128-aac}"

# Resolve .pls/.m3u playlists to raw stream URL (ffmpeg can't handle playlists natively)
if [[ "$STREAM_URL" == *.pls* || "$STREAM_URL" == *.m3u* ]]; then
  echo "Resolving playlist: $STREAM_URL"
  if [[ -f "$STREAM_URL" ]]; then
    PLAYLIST_CONTENT=$(cat "$STREAM_URL" 2>/dev/null || true)
  else
    PLAYLIST_CONTENT=$(curl -fsSL "$STREAM_URL" 2>/dev/null || true)
  fi
  RESOLVED=$(echo "$PLAYLIST_CONTENT" | grep -i -m1 "^File[0-9]*=" | cut -d= -f2- | tr -d '\r' | xargs || true)
  if [[ -z "$RESOLVED" ]]; then
    RESOLVED=$(echo "$PLAYLIST_CONTENT" | grep -m1 -oE "https?://[^[:space:]\"]+" | tr -d '\r' | head -n1 || true)
  fi
  if [[ -n "$RESOLVED" ]]; then
    echo "Resolved playlist to: $RESOLVED"
    STREAM_URL="$RESOLVED"
  else
    echo "ERROR: Could not resolve playlist '$1' to a stream URL" >&2
    echo "Playlist content was:" >&2
    echo "$PLAYLIST_CONTENT" | head -n 20 >&2
    exit 1
  fi
fi

echo "Initiating degraded capture pipeline for: $STREAM_URL"
echo "Target destination: $(pwd)"
echo "Press [q] inside this terminal to stop recording gracefully."
echo "------------------------------------------------------------"

ffmpeg -y -loglevel info -stats -i "$STREAM_URL" \
  -filter_complex "aevalsrc=exprs='(random(0)-0.5)*0.009|(random(1)-0.5)*0.009':s=44100[static]; \
  [0:a][static]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0[mixed]; \
  [mixed]vibrato=f=2.3:d=0.022,vibrato=f=16.5:d=0.006,highpass=f=50,lowpass=f=13000, \
  equalizer=f=500:width_type=q:width=0.8:g=-1.2,equalizer=f=6000:width_type=q:width=0.7:g=-4[out]" \
  -map "[out]" -c:a aac -b:a 192k \
  -f segment \
  -segment_time 2700 \
  -strftime 1 \
  "./dronezone_cassette_%Y-%m-%d_%H-%M-%S.aac"