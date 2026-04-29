#!/usr/bin/env python3
"""Build cities.bin from GeoNames cities15000.txt + countryInfo.txt.

Output format (little-endian):
    u32 num_cities
    repeat num_cities times:
        u8  tier        (1..5)
        u8  is_capital  (0/1)
        i32 population
        f32 lat
        f32 lon
        u16 name_len ; bytes name (UTF-8)
        u16 country_len ; bytes country (UTF-8)

Tiers (each city tagged with its lowest qualifying tier):
    1 = capital of country with population > 30M
    2 = any capital
    3 = any city with population > 1_000_000
    4 = any city with population > 100_000
    5 = any city with population > 15_000  (i.e. all cities15000 entries)

A city present in tier N is also implicitly available at tiers N+1..5
(filters at runtime use tier <= chosen_tier).

The source files are fetched from download.geonames.org on first run.
"""

from __future__ import annotations

import io
import os
import struct
import sys
import urllib.request
import zipfile
from pathlib import Path

CITIES_URL = "https://download.geonames.org/export/dump/cities15000.zip"
COUNTRY_URL = "https://download.geonames.org/export/dump/countryInfo.txt"
CITIES_CACHE = "/tmp/cities15000.txt"
COUNTRY_CACHE = "/tmp/geonames_countryInfo.txt"

LARGE_COUNTRY_THRESHOLD = 30_000_000


def fetch_cities() -> str:
    if not os.path.exists(CITIES_CACHE):
        sys.stderr.write(f"fetch {CITIES_URL}\n")
        with urllib.request.urlopen(CITIES_URL, timeout=60) as r:
            buf = r.read()
        with zipfile.ZipFile(io.BytesIO(buf)) as zf:
            with zf.open("cities15000.txt") as f:
                with open(CITIES_CACHE, "wb") as out:
                    out.write(f.read())
    with open(CITIES_CACHE, "r", encoding="utf-8") as fh:
        return fh.read()


def fetch_country_info() -> str:
    if not os.path.exists(COUNTRY_CACHE):
        sys.stderr.write(f"fetch {COUNTRY_URL}\n")
        req = urllib.request.Request(
            COUNTRY_URL, headers={"User-Agent": "miaou-geo-quiz/1.0"}
        )
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
        with open(COUNTRY_CACHE, "wb") as fh:
            fh.write(data)
    with open(COUNTRY_CACHE, "r", encoding="utf-8") as fh:
        return fh.read()


def parse_country_info(text: str) -> tuple[
    dict[str, str], dict[str, int], dict[str, str]
]:
    """Return (iso2 -> capital_name, iso2 -> population, iso2 -> country_name)."""
    capital = {}
    population = {}
    name = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) < 8:
            continue
        iso2 = f[0]
        country = f[4]
        cap = f[5]
        try:
            pop = int(f[7] or "0")
        except ValueError:
            pop = 0
        capital[iso2] = cap
        population[iso2] = pop
        name[iso2] = country
    return capital, population, name


def main() -> None:
    out = (
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent / "data" / "cities.bin"
    )

    cap_by_iso, pop_by_iso, country_name = parse_country_info(fetch_country_info())
    large_countries = {iso for iso, p in pop_by_iso.items() if p >= LARGE_COUNTRY_THRESHOLD}

    cities_raw = fetch_cities()
    selected: list[tuple[int, int, int, float, float, str, str]] = []
    # Format reference:
    # 0 geonameid, 1 name, 2 ascii_name, 3 alt_names, 4 lat, 5 lon,
    # 6 feat_class, 7 feat_code, 8 country_code, 9 cc2, 10 admin1,
    # 11 admin2, 12 admin3, 13 admin4, 14 population, 15 elevation,
    # 16 dem, 17 timezone, 18 modification_date
    for line in cities_raw.splitlines():
        f = line.split("\t")
        if len(f) < 15:
            continue
        name = f[1].strip()
        ascii_name = f[2].strip()
        try:
            lat = float(f[4])
            lon = float(f[5])
        except ValueError:
            continue
        feat_code = f[7]
        iso = f[8]
        try:
            pop = int(f[14] or "0")
        except ValueError:
            pop = 0

        is_capital = feat_code == "PPLC"
        # Capitals in countryInfo can disagree with geonames (admin disputes); be lenient.
        if not is_capital and cap_by_iso.get(iso, "") == name:
            is_capital = True

        if is_capital and iso in large_countries:
            tier = 1
        elif is_capital:
            tier = 2
        elif pop >= 1_000_000:
            tier = 3
        elif pop >= 100_000:
            tier = 4
        else:
            tier = 5

        country = country_name.get(iso, iso)
        # Prefer ASCII for terminal compatibility
        display_name = ascii_name or name
        selected.append((tier, 1 if is_capital else 0, pop, lat, lon, display_name, country))

    # Sort: tier asc, then population desc — newer rounds get the "easier" cities
    # within their tier first.
    selected.sort(key=lambda c: (c[0], -c[2]))

    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "wb") as fh:
        fh.write(struct.pack("<I", len(selected)))
        for tier, is_capital, pop, lat, lon, name, country in selected:
            name_b = name.encode("utf-8")
            country_b = country.encode("utf-8")
            fh.write(struct.pack("<BBiff", tier, is_capital, pop, lat, lon))
            fh.write(struct.pack("<H", len(name_b)))
            fh.write(name_b)
            fh.write(struct.pack("<H", len(country_b)))
            fh.write(country_b)

    by_tier = {t: 0 for t in range(1, 6)}
    for c in selected:
        by_tier[c[0]] += 1
    sys.stderr.write(
        f"wrote {out}  total={len(selected)} "
        f"by_tier={by_tier} size={out.stat().st_size}B\n"
    )


if __name__ == "__main__":
    main()
