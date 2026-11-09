import os

import psycopg


def test_initial_schema_is_applied():
    database_url = os.environ["DATABASE_URL"]
    with psycopg.connect(database_url) as connection:
        rows = connection.execute(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema = 'public'"
        ).fetchall()
    table_names = {row[0] for row in rows}
    expected = {
        "organizations", "users", "organization_members", "warehouses",
        "product_categories", "products", "suppliers", "customers",
        "purchase_invoices", "purchase_lines", "sales_invoices", "sales_lines",
        "stock_movements", "payments", "sync_requests", "audit_logs",
        "schema_migrations",
    }
    assert expected.issubset(table_names)
