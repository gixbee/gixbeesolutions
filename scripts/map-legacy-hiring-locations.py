"""Map legacy location text only when one hiring place or alias matches exactly."""
from __future__ import annotations

import argparse


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database-url", required=True)
    args = parser.parse_args()
    try:
        import psycopg
    except ImportError as exc:
        raise SystemExit("Install psycopg before mapping locations") from exc
    conn = psycopg.connect(args.database_url)
    sql = """
    WITH matches AS (
      SELECT src.table_name, src.id, loc.id AS location_id
      FROM (
        SELECT 'job_preferences' AS table_name, id::text AS id, "preferredLocation" AS label
        FROM job_preferences WHERE "locationId" IS NULL AND COALESCE("preferredLocation", '') <> ''
        UNION ALL
        SELECT 'hiring_requests', id::text, location FROM hiring_requests
        WHERE "locationId" IS NULL AND COALESCE(location, '') <> ''
        UNION ALL
        SELECT 'talent_profiles', id::text, "addressText" FROM talent_profiles
        WHERE "locationId" IS NULL AND COALESCE("addressText", '') <> ''
      ) src
      JOIN (
        SELECT id, lower(name) AS label FROM hiring_locations WHERE "isActive" AND kind = 'PLACE'
        UNION ALL
        SELECT "locationId", lower(alias) FROM hiring_location_aliases
      ) loc ON loc.label = lower(btrim(src.label))
    ), unique_matches AS (
      SELECT table_name, id, min(location_id) AS location_id
      FROM matches GROUP BY table_name, id HAVING count(DISTINCT location_id) = 1
    )
    SELECT table_name, id, location_id FROM unique_matches
    """
    with conn, conn.cursor() as cur:
        cur.execute(sql)
        rows = cur.fetchall()
        for table, row_id, location_id in rows:
            cur.execute(
                f'''UPDATE {table} SET "locationId" = %s, "locationMatchStatus" = 'MAPPED' WHERE id::text = %s AND "locationId" IS NULL''',
                (location_id, row_id),
            )
        print(f"Mapped {len(rows)} unambiguous locations. Other rows stay UNRESOLVED.")


if __name__ == "__main__":
    main()
