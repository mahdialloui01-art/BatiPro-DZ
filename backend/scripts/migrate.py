import os
from pathlib import Path

import psycopg


def main() -> None:
    database_url = os.getenv("DATABASE_URL", "").strip()
    if not database_url:
        raise SystemExit("DATABASE_URL is required")
    migration = Path(__file__).resolve().parents[1] / "migrations" / "001_initial_schema.sql"
    sql = migration.read_text(encoding="utf-8")
    with psycopg.connect(database_url) as connection:
        with connection.cursor() as cursor:
            cursor.execute(sql)
    print(f"Applied {migration.name}")


if __name__ == "__main__":
    main()
