"""Import GeoNames India into hiring_locations. See docs/hiring-locations.md.

Does not download data and does not invent places. Re-runs upsert on sourceKey.
"""
from __future__ import annotations

import argparse
import csv
from pathlib import Path

# Official renames. Applied only when exactly one imported place has the canonical name.
RENAMES = {
    "thiruvananthapuram": ["trivandrum"],
    "mumbai": ["bombay"],
    "chennai": ["madras"],
    "kolkata": ["calcutta"],
    "bengaluru": ["bangalore"],
    "gurugram": ["gurgaon"],
    "kochi": ["cochin"],
    "puducherry": ["pondicherry"],
    "vadodara": ["baroda"],
    "varanasi": ["banaras", "benares"],
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", required=True, help="Directory with IN.txt, admin1CodesASCII.txt, admin2Codes.txt")
    parser.add_argument("--database-url", required=True)
    args = parser.parse_args()
    folder = Path(args.dir)
    try:
        import psycopg
    except ImportError as exc:
        raise SystemExit("Install psycopg before importing locations") from exc

    admin1 = {}
    with (folder / "admin1CodesASCII.txt").open(encoding="utf-8") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 2 or not parts[0].startswith("IN."):
                continue
            admin1[parts[0]] = parts[1]
    admin2 = {}
    with (folder / "admin2Codes.txt").open(encoding="utf-8") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2 and parts[0].startswith("IN."):
                admin2[parts[0]] = parts[1]

    conn = psycopg.connect(args.database_url)
    with conn, conn.cursor() as cur:
        for code, name in admin1.items():
            cur.execute(
                """INSERT INTO hiring_locations (id, kind, name, source, "sourceKey")
                   VALUES (%s, 'STATE', %s, 'geonames', %s)
                   ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, "updatedAt"=NOW()""",
                (f"state-{code}", name, f"geonames-admin1:{code}"),
            )
        for code, name in admin2.items():
            state_code = ".".join(code.split(".")[:2])
            cur.execute(
                """INSERT INTO hiring_locations (id, kind, name, "parentId", "stateId", "stateName", source, "sourceKey")
                   VALUES (%s, 'DISTRICT', %s, %s, %s, %s, 'geonames', %s)
                   ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, "stateName"=EXCLUDED."stateName", "updatedAt"=NOW()""",
                (
                    f"district-{code}",
                    name,
                    f"state-{state_code}",
                    f"state-{state_code}",
                    admin1.get(state_code, ""),
                    f"geonames-admin2:{code}",
                ),
            )
        names: dict[str, list[str]] = {}
        with (folder / "IN.txt").open(encoding="utf-8") as handle:
            for row in csv.reader(handle, delimiter="\t"):
                if len(row) < 11 or row[6] == "A":
                    continue
                geoname_id, name, lat, lng = row[0], row[1], row[4], row[5]
                feature = row[7]
                if feature not in {"PPL", "PPLA", "PPLA2", "PPLA3", "PPLA4", "PPLC", "PPLG", "PPLX"}:
                    continue
                admin1_code = f"IN.{row[10]}" if row[10] else ""
                admin2_code = f"IN.{row[10]}.{row[11]}" if len(row) > 11 and row[10] and row[11] else ""
                place_id = f"geonames-{geoname_id}"
                cur.execute(
                    """INSERT INTO hiring_locations
                       (id, kind, name, "parentId", "stateId", "districtId", "stateName", "districtName", lat, lng, source, "sourceKey")
                       VALUES (%s,'PLACE',%s,%s,%s,%s,%s,%s,%s,%s,'geonames',%s)
                       ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, lat=EXCLUDED.lat, lng=EXCLUDED.lng,
                         "stateName"=EXCLUDED."stateName", "districtName"=EXCLUDED."districtName", "updatedAt"=NOW()""",
                    (
                        place_id,
                        name,
                        f"district-{admin2_code}" if admin2_code in admin2 else None,
                        f"state-{admin1_code}" if admin1_code in admin1 else None,
                        f"district-{admin2_code}" if admin2_code in admin2 else None,
                        admin1.get(admin1_code, ""),
                        admin2.get(admin2_code, ""),
                        lat or None,
                        lng or None,
                        f"geonames:{geoname_id}",
                    ),
                )
                names.setdefault(name.lower(), []).append(place_id)
        for canonical, aliases in RENAMES.items():
            ids = names.get(canonical, [])
            if len(ids) != 1:
                continue
            for alias in aliases:
                cur.execute(
                    """INSERT INTO hiring_location_aliases ("locationId", alias) VALUES (%s, %s)
                       ON CONFLICT DO NOTHING""",
                    (ids[0], alias),
                )
    print("Imported GeoNames India places, states and districts")


if __name__ == "__main__":
    main()
