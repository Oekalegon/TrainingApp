#!/usr/bin/env python3
"""Writes a synthetic GPX track that follows one of the watch simulator's test workouts.

    Tools/make-interval-gpx.py [--alert] [output.gpx]

Without `--alert`: the `-fakeIntervalPlan` workout (below), written to TestTracks/short-intervals.gpx.
With `--alert`: the `-fakeAlertPlan` workout, written to TestTracks/alert-test.gpx: 60 s warm-up,
4 x (90 s zone 4, 90 s zone 2), 60 s cool-down (14 minutes), long enough for the zone alerts to
fire. The heart rate goes out of the step's zone for a stretch in most steps (see ALERT_STEPS), so
every alert can be seen: too high, too low, far above, far below, repeats, back in the zone, and
the quiet climb at the start of a hard step.

The `-fakeIntervalPlan` workout:

The workout: 60 s warm-up (zone 1), 6 x (20 s zone 4, 20 s zone 2), 60 s cool-down (zone 1), so
6 minutes in all. The track is a circle run at the pace of each step, with a heart rate that
moves towards each step's level over a few seconds, as a real one does, so the first seconds of
every hard step are still below zone 4. Heart rates assume `-fakeZones` (resting 55, maximum 190). Most steps end in their zone, but
some go above or below it, so the zone alerts can be tested; see the table below.
TestWorkoutTrackTests checks the track against the zones.

Nothing here is a real run or a real place, so the file can live in the repo.

"""
import math
import sys
from pathlib import Path
from datetime import datetime, timedelta, timezone

# The heart rate each hard and each easy step moves towards, by repetition. Most are in their zone
# (zone 4 is about 163-177 and zone 2 about 136-150 with `-fakeZones`); some are not, so the
# alerts get tested:
#   rep 2 hard: far above zone 4 (190)        rep 3 easy: below zone 2 (128, down in zone 1)
#   rep 4 hard: far below zone 4 (140)        rep 5 easy: above zone 2 (156, in zone 3)
#   rep 6 hard: a little below zone 4 (158)
HARD_HEART_RATES = [169, 190, 169, 140, 169, 158]
EASY_HEART_RATES = [141, 141, 128, 141, 156, 141]

# (seconds, speed in m/s, target heart rate)
STEPS = [(60, 2.8, 126)]
for hard, easy in zip(HARD_HEART_RATES, EASY_HEART_RATES):
    STEPS += [(20, 4.5, hard), (20, 2.5, easy)]
STEPS += [(60, 2.5, 126)]

# The alert test: each step is a list of (seconds, target heart rate) legs, so the heart rate can
# leave the zone part-way through a step. Zone 4 is about 163-177, zone 2 136-150 and zone 3 150-163
# with `-fakeZones`; the heart rate moves towards each leg's target with a 6 s time constant.
#   hard 1: in zone 4 from about 20 s in (the climb at the start is quiet, then "back in zone")
#   hard 2: above zone 4 from 25 s (181, a little), and far above from 45 s (190), back in at 70 s
#   hard 3: below zone 4 from 30 s (156), and far below from 50 s (145), back in at 70 s
#   hard 4: never gets there (155, in zone 3): too low, repeated (the first may be far, while it is still climbing)
#   easy 1: in zone 2 (the fall from zone 4 is quiet, then "back in zone")
#   easy 2: above zone 2 from 30 s (156), back at 70 s
#   easy 3: below zone 2 from 30 s (128, down in zone 1), back at 70 s
#   easy 4: stays above zone 2 (158, in zone 3): too high, repeated
ALERT_STEPS = [
    (60, 2.8, [(60, 126)]),
    (90, 4.5, [(90, 169)]),
    (90, 2.5, [(90, 141)]),
    (90, 4.5, [(25, 169), (20, 181), (25, 190), (20, 169)]),
    (90, 2.5, [(30, 141), (40, 156), (20, 141)]),
    (90, 4.5, [(30, 169), (20, 156), (20, 145), (20, 169)]),
    (90, 2.5, [(30, 141), (40, 128), (20, 141)]),
    (90, 4.5, [(90, 155)]),
    (90, 2.5, [(90, 158)]),
    (60, 2.5, [(60, 126)]),
]
if "--alert" in sys.argv:
    sys.argv.remove("--alert")
    OUTPUT_NAME = "alert-test.gpx"
    TRACK_NAME = "Alert test (synthetic)"
    LEGS = [(seconds, speed) + (target,) for _, speed, legs in ALERT_STEPS for seconds, target in legs]
else:
    OUTPUT_NAME = "short-intervals.gpx"
    TRACK_NAME = "Short intervals (synthetic)"
    LEGS = STEPS
HR_TIME_CONSTANT = 6.0  # seconds a heart rate takes to move about two thirds of the way
START_HR = 100.0
CENTRE = (52.0, 5.0)  # an arbitrary spot on the map
METRES_PER_DEGREE_LAT = 111_320.0

total_distance = sum(seconds * speed for seconds, speed, _ in LEGS)
radius = total_distance / (2 * math.pi)  # one lap of a circle for the whole workout

start = datetime(2026, 1, 1, 8, 0, 0, tzinfo=timezone.utc)
points = []
distance, heart_rate, second = 0.0, START_HR, 0
points.append((second, distance, heart_rate))
for seconds, speed, target in LEGS:
    for _ in range(seconds):
        second += 1
        distance += speed
        heart_rate += (target - heart_rate) * (1 - math.exp(-1 / HR_TIME_CONSTANT))
        points.append((second, distance, heart_rate))

lines = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<gpx version="1.1" creator="TrainingApp make-interval-gpx.py" xmlns="http://www.topografix.com/GPX/1/1"'
    ' xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">',
    f"<trk><name>{TRACK_NAME}</name><trkseg>",
]
for second, travelled, bpm in points:
    angle = travelled / radius
    north = radius * math.sin(angle)
    east = radius * (1 - math.cos(angle))
    lat = CENTRE[0] + north / METRES_PER_DEGREE_LAT
    lon = CENTRE[1] + east / (METRES_PER_DEGREE_LAT * math.cos(math.radians(CENTRE[0])))
    time = (start + timedelta(seconds=second)).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines.append(
        f'<trkpt lat="{lat:.6f}" lon="{lon:.6f}"><ele>10</ele><time>{time}</time>'
        f"<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>{round(bpm)}</gpxtpx:hr>"
        "</gpxtpx:TrackPointExtension></extensions></trkpt>")
lines.append("</trkseg></trk></gpx>")

path = sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).parent / "TestTracks" / OUTPUT_NAME)
with open(path, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"{path}: {len(points)} points, {total_distance:.0f} m, {second} s")
