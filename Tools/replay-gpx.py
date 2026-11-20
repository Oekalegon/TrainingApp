#!/usr/bin/env python3
"""Replay a GPX track into a booted simulator as GPS fixes, optionally sped up.

    Tools/replay-gpx.py track.gpx [--device UDID|booted] [--speed 10] [--start-min 0] [--minutes 5] [--prime]

Uses `xcrun simctl location <device> set lat,lon`, honouring the track's own timestamps divided
by --speed. Keep GPX files out of the repo: they hold real locations.
"""
import argparse
import subprocess
import time
import xml.etree.ElementTree as ET
from datetime import datetime

parser = argparse.ArgumentParser()
parser.add_argument("gpx")
parser.add_argument("--device", default="booted")
parser.add_argument("--speed", type=float, default=10.0, help="playback speed multiplier")
parser.add_argument("--start-min", type=float, default=0.0, help="start this many track minutes in")
parser.add_argument("--minutes", type=float, default=None, help="track minutes to play")
parser.add_argument("--prime", action="store_true", help="only move the simulator to the track's start, then exit")
parser.add_argument("--min-interval", type=float, default=0.5, help="min real seconds between fixes")
args = parser.parse_args()

points = []
for pt in ET.parse(args.gpx).getroot().iter("{http://www.topografix.com/GPX/1/1}trkpt"):
    stamp = pt.find("{http://www.topografix.com/GPX/1/1}time").text.replace("Z", "+00:00")
    points.append((datetime.fromisoformat(stamp).timestamp(), pt.get("lat"), pt.get("lon")))
if not points:
    raise SystemExit("no trkpt found")

t0 = points[0][0] + args.start_min * 60
t1 = t0 + args.minutes * 60 if args.minutes else points[-1][0]
points = [p for p in points if t0 <= p[0] <= t1]

if args.prime:
    subprocess.run(["xcrun", "simctl", "location", args.device, "set", f"{points[0][1]},{points[0][2]}"], check=True)
    raise SystemExit(0)

began = time.monotonic()
last_sent = -1e9
for stamp, lat, lon in points:
    due = (stamp - t0) / args.speed
    if due - last_sent < args.min_interval:
        continue
    delay = due - (time.monotonic() - began)
    if delay > 0:
        time.sleep(delay)
    subprocess.run(["xcrun", "simctl", "location", args.device, "set", f"{lat},{lon}"], check=True)
    last_sent = due
print(f"replayed {len(points)} track points")
