#!/bin/bash

# Enforce strict error handling
set -e

# Default to primary relay if no argument is provided
STREAM_URL="${1:-http://ice6.somafm.com/dronezone-128-aac}"

# Resolve .pls/.m3u playlists to raw stream URL
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
    exit 1
  fi
fi

echo "Initiating degraded capture pipeline for: $STREAM_URL"
echo "Target destination: $(pwd)"
echo "Press [q] inside this terminal to stop recording gracefully."
echo "------------------------------------------------------------"

ffmpeg -y -loglevel info -stats -i "$STREAM_URL" \
  -filter_complex "aevalsrc=exprs='(random(0)-0.5)*0.005|(random(1)-0.5)*0.005':s=44100[static]; \
  [0:a][static]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0[mixed]; \
  [mixed]vibrato=f=2.1:d=0.018,vibrato=f=13.5:d=0.004,highpass=f=35,lowpass=f=15000, \
  equalizer=f=150:width_type=q:width=1.0:g=2.5,equalizer=f=7000:width_type=q:width=0.8:g=-2.5[out]" \
  -map "[out]" -c:a aac -b:a 192k \
  -f segment \
  -segment_time 2700 \
  -strftime 1 \
  "./dronezone_cassette_%Y-%m-%d_%H-%M-%S.aac"