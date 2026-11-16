# Hiring location master

This catalogue is separate from serviceable cities (`cities`), which still control where Gixbee services, banners and businesses operate.

## Source

Importer: `scripts/import-hiring-locations.py`

| Piece | Source | Licence | Coverage |
| --- | --- | --- | --- |
| States, districts and populated places with coordinates | [GeoNames India dump](https://download.geonames.org/export/dump/IN.zip) plus `admin1CodesASCII.txt` and `admin2Codes.txt` | [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/) | Populated places GeoNames lists for India. Admin1 is states and union territories. Admin2 is districts. This is not a complete census of every village. |
| Alternate names | `alternateNamesV2.txt` filtered to the imported GeoNames ids | Same CC BY 4.0 licence | Names GeoNames publishes. The importer also adds a short, documented alias list (Trivandrum for Thiruvananthapuram, and similar official renames) only when exactly one imported place has the canonical name. |

A fuller village list without coordinates is the [Local Government Directory](https://lgdirectory.gov.in/) published as government open data. It is not bundled, because this master needs coordinates for nearby matching and the file is not redistributed here.

The repository does not contain a fabricated India-wide place list. Search stays empty until the import runs.

## Import

Download the GeoNames files into one directory, then:

```
python scripts/import-hiring-locations.py --dir path/to/geonames --database-url postgresql://...
```

Re-running upserts on `sourceKey` (`geonames:<id>`) and does not duplicate rows.

## Legacy text

`scripts/map-legacy-hiring-locations.py` sets `locationId` only when the stored text matches exactly one active place name or alias. Anything else stays `locationMatchStatus = UNRESOLVED` for correction. Typed street addresses stay in `addressText` or the existing location text column.
