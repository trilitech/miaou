#!/usr/bin/env python3
"""Build landmask.bin from Natural Earth ne_50m_land polygons.

Rasterizes the land polygons to a 720×360 1°-per-2-pixel bitmap (rows are
latitude bands from north to south, columns are longitude from west to
east). The output is packed: 1 bit per pixel, MSB-first within each byte.

Pure-Python scanline polygon fill so no PIL/Pillow dependency is needed.

Output format (little-endian):
    u16 width
    u16 height
    bytes data  (width*height/8 bytes, packed MSB-first)

Usage:
    python3 build_landmask.py [out_path]

Source file ne_50m_land.geojson is fetched from nvkelso/natural-earth-vector
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
    "master/geojson/ne_50m_land.geojson"
)
CACHE = "/tmp/ne_50m_land.geojson"
WIDTH = 720
HEIGHT = 360


def fetch() -> bytes:
    if not os.path.exists(CACHE):
        sys.stderr.write(f"fetch {URL}\n")
        with urllib.request.urlopen(URL, timeout=30) as r:
            data = r.read()
        with open(CACHE, "wb") as fh:
            fh.write(data)
    with open(CACHE, "rb") as fh:
        return fh.read()


def lonlat_to_xy(lon: float, lat: float) -> tuple[float, float]:
    x = (lon + 180.0) / 360.0 * WIDTH
    y = (90.0 - lat) / 180.0 * HEIGHT
    return (x, y)


def fill_polygon(grid: bytearray, ring: list[tuple[float, float]], value: int) -> None:
    """Scanline polygon fill into a row-major bytearray of WIDTH*HEIGHT bytes.
    `value` is 1 to fill (land) or 0 to subtract (hole)."""
    if len(ring) < 3:
        return
    ymin = max(0, int(min(p[1] for p in ring)))
    ymax = min(HEIGHT - 1, int(max(p[1] for p in ring)) + 1)
    n = len(ring)
    for y in range(ymin, ymax + 1):
        yc = y + 0.5
        xs: list[float] = []
        for i in range(n):
            x0, y0 = ring[i]
            x1, y1 = ring[(i + 1) % n]
            if (y0 <= yc < y1) or (y1 <= yc < y0):
                t = (yc - y0) / (y1 - y0)
                xs.append(x0 + t * (x1 - x0))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            x0 = max(0, int(xs[i]))
            x1 = min(WIDTH, int(xs[i + 1]) + 1)
            base = y * WIDTH
            for x in range(x0, x1):
                grid[base + x] = value


def main() -> None:
    out = (
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent / "data" / "landmask.bin"
    )
    geojson = json.loads(fetch())
    grid = bytearray(WIDTH * HEIGHT)
    n_polys = 0
    for feat in geojson["features"]:
        geom = feat["geometry"]
        if geom["type"] == "Polygon":
            polys = [geom["coordinates"]]
        elif geom["type"] == "MultiPolygon":
            polys = geom["coordinates"]
        else:
            continue
        for poly in polys:
            outer = [lonlat_to_xy(lon, lat) for lon, lat in poly[0]]
            fill_polygon(grid, outer, 1)
            n_polys += 1
            for hole in poly[1:]:
                ring = [lonlat_to_xy(lon, lat) for lon, lat in hole]
                fill_polygon(grid, ring, 0)

    # Pack to 1 bit per pixel, MSB first.
    packed = bytearray((WIDTH * HEIGHT + 7) // 8)
    for i, v in enumerate(grid):
        if v:
            packed[i >> 3] |= 0x80 >> (i & 7)

    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "wb") as fh:
        fh.write(struct.pack("<HH", WIDTH, HEIGHT))
        fh.write(packed)

    set_bits = sum(bin(b).count("1") for b in packed)
    sys.stderr.write(
        f"wrote {out}  size={out.stat().st_size}B  polygons={n_polys} "
        f"land_pixels={set_bits}/{WIDTH*HEIGHT} ({WIDTH}x{HEIGHT})\n"
    )


if __name__ == "__main__":
    main()
