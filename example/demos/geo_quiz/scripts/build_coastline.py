#!/usr/bin/env python3
"""Build coastline.bin from Natural Earth ne_110m_coastline.

Output format (little-endian):
    u32 num_segments
    repeat num_segments times:
        u16 num_points
        repeat num_points times:
            i16 lat_deci  (latitude * 10, range -900..900)
            i16 lon_deci  (longitude * 10, range -1800..1800)

A "segment" is a polyline of consecutive coastline points. Sentinels in
ne_110m_coastline keep individual segments small (~10-200 points each).

Usage:
    python3 build_coastline.py [out_path]

If [out_path] is omitted, writes ../data/coastline.bin relative to the script.

The source file is fetched from the nvkelso/natural-earth-vector mirror
on first run and cached in /tmp.
"""

from __future__ import annotations

import json
import os
import struct
import sys
import urllib.request
from pathlib import Path

URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_50m_coastline.geojson"
)
CACHE = "/tmp/ne_50m_coastline.geojson"


def fetch() -> bytes:
    if not os.path.exists(CACHE):
        sys.stderr.write(f"fetch {URL}\n")
        with urllib.request.urlopen(URL, timeout=30) as r:
            data = r.read()
        with open(CACHE, "wb") as fh:
            fh.write(data)
    with open(CACHE, "rb") as fh:
        return fh.read()


def main() -> None:
    out = (
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent / "data" / "coastline.bin"
    )
    geojson = json.loads(fetch())
    segments: list[list[tuple[int, int]]] = []
    for feat in geojson["features"]:
        geom = feat["geometry"]
        if geom["type"] == "LineString":
            lines = [geom["coordinates"]]
        elif geom["type"] == "MultiLineString":
            lines = geom["coordinates"]
        else:
            continue
        for line in lines:
            pts = [
                (
                    max(-900, min(900, int(round(lat * 10)))),
                    max(-1800, min(1800, int(round(lon * 10)))),
                )
                for lon, lat in line
            ]
            if len(pts) >= 2:
                segments.append(pts)

    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "wb") as fh:
        fh.write(struct.pack("<I", len(segments)))
        for seg in segments:
            fh.write(struct.pack("<H", len(seg)))
            for lat, lon in seg:
                fh.write(struct.pack("<hh", lat, lon))

    total_pts = sum(len(s) for s in segments)
    sys.stderr.write(
        f"wrote {out}  segments={len(segments)} points={total_pts} "
        f"size={out.stat().st_size}B\n"
    )


if __name__ == "__main__":
    main()
