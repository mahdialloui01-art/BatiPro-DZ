import os
from pathlib import Path

import psycopg


def main() -> None:
    database_url = os.getenv("DATABASE_URL", "").strip()
    if not database_url:
        raise SystemExit("DATABASE_URL is required")
    migrations_dir = Path(__file__).resolve().parents[1] / "migrations"
    migrations = sorted(migrations_dir.glob("*.sql"))
    if not migrations:
        raise SystemExit("No SQL migrations found")
    with psycopg.connect(database_url) as connection:
        with connection.cursor() as cursor:
            for migration in migrations:
                cursor.execute(migration.read_text(encoding="utf-8"))
                print(f"Applied {migration.name}")


if __name__ == "__main__":
    main()
