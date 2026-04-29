# Data sources

The geographic data shipped under this directory is derived from public-domain
and openly-licensed datasets:

## Coastline — `coastline.bin`

Derived from **Natural Earth** `ne_110m_coastline` (1:110-million world
coastline at 0.1° quantisation).

- Source: <https://www.naturalearthdata.com/>
- Mirror used at build time:
  <https://github.com/nvkelso/natural-earth-vector>
- License: public domain (Natural Earth uses CC0 / public domain dedication)

The build script `scripts/build_coastline.py` fetches the GeoJSON and packs the
LineString features into a small binary stream (`int16` lat/lon at 0.1°
precision).

## Cities — `cities.bin`

Derived from **GeoNames** `cities15000.txt` (every city / settlement with a
population ≥ 15 000) and `countryInfo.txt`.

- Source: <https://www.geonames.org/>
- License: Creative Commons Attribution 4.0 International (CC BY 4.0)
  <https://creativecommons.org/licenses/by/4.0/>

The build script `scripts/build_cities.py` filters and re-encodes the dataset,
tagging each city with a difficulty tier based on its `is_capital` flag and
population, plus the population of its country (loaded from
`countryInfo.txt`).

If you redistribute the binary: please retain this attribution notice.
