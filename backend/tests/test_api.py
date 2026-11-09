import os
from uuid import uuid4

from fastapi.testclient import TestClient

from app.main import app


def test_registration_login_and_tenant_scoped_stock_api(monkeypatch):
    monkeypatch.setenv("BATIPRO_TOKEN_SECRET", "test-token-secret-that-is-at-least-32-bytes")
    monkeypatch.setenv("BATIPRO_BOOTSTRAP_SECRET", "bootstrap-secret-for-integration-tests")
    email = f"test-{uuid4().hex}@example.test"

    with TestClient(app) as client:
        registered = client.post("/auth/register", json={
            "email": email,
            "password": "Strong-test-password-123",
            "display_name": "Test Owner",
            "organization_name": "Test Store",
            "bootstrap_secret": "bootstrap-secret-for-integration-tests",
        })
        assert registered.status_code == 201, registered.text
        token = registered.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        profile = client.get("/me", headers=headers)
        assert profile.status_code == 200
        assert profile.json()["organization_name"] == "Test Store"

        login = client.post("/auth/login", json={
            "email": email,
            "password": "Strong-test-password-123",
        })
        assert login.status_code == 200
        assert login.json()["token_type"] == "bearer"

        unauthorized = client.get("/products")
        assert unauthorized.status_code == 401

        created = client.post("/products", headers=headers, json={
            "name": "حديد تسليح T12",
            "category": "حديد التسليح",
            "base_unit": "قضيب",
            "tracking_mode": "piece",
            "piece_weight_kg": "10.656",
            "rebar_diameter_mm": "12",
            "bar_length_m": "12",
            "purchase_price": "800",
            "sale_price": "950",
            "minimum_stock": "5",
        })
        assert created.status_code == 201, created.text
        product_id = created.json()["id"]

        warehouse_response = client.get("/warehouses", headers=headers)
        assert warehouse_response.status_code == 200
        warehouse_id = warehouse_response.json()[0]["id"]

        key = f"opening-{uuid4().hex}"
        adjustment = {
            "product_id": product_id,
            "warehouse_id": warehouse_id,
            "quantity_delta": "10",
            "unit": "قضيب",
            "reason": "رصيد افتتاحي للاختبار",
            "idempotency_key": key,
        }
        first = client.post("/stock/adjustments", headers=headers, json=adjustment)
        assert first.status_code == 201, first.text
        assert first.json()["duplicate"] is False

        duplicate = client.post("/stock/adjustments", headers=headers, json=adjustment)
        assert duplicate.status_code == 201
        assert duplicate.json()["duplicate"] is True

        stock = client.get("/stock", headers=headers)
        assert stock.status_code == 200
        assert any(row["product_id"] == product_id and row["quantity"] == "10.000"
                   for row in stock.json())

        insufficient = client.post("/stock/adjustments", headers=headers, json={
            **adjustment,
            "quantity_delta": "-11",
            "idempotency_key": f"sale-{uuid4().hex}",
        })
        assert insufficient.status_code == 409


def test_registration_requires_bootstrap_secret(monkeypatch):
    monkeypatch.setenv("BATIPRO_BOOTSTRAP_SECRET", "correct-bootstrap-secret-value")
    with TestClient(app) as client:
        response = client.post("/auth/register", json={
            "email": f"blocked-{uuid4().hex}@example.test",
            "password": "Strong-test-password-123",
            "display_name": "Blocked",
            "organization_name": "Blocked Store",
            "bootstrap_secret": "wrong-secret",
        })
    assert response.status_code == 403

def test_purchase_and_sale_post_atomically_update_stock(monkeypatch):
    monkeypatch.setenv("BATIPRO_TOKEN_SECRET", "test-token-secret-that-is-at-least-32-bytes")
    monkeypatch.setenv("BATIPRO_BOOTSTRAP_SECRET", "bootstrap-secret-for-integration-tests")
    email = f"trade-{uuid4().hex}@example.test"

    with TestClient(app) as client:
        registered = client.post("/auth/register", json={
            "email": email,
            "password": "Strong-test-password-123",
            "display_name": "Trade Owner",
            "organization_name": "Trade Store",
            "bootstrap_secret": "bootstrap-secret-for-integration-tests",
        })
        assert registered.status_code == 201, registered.text
        headers = {"Authorization": f"Bearer {registered.json()['access_token']}"}
        warehouse = client.get("/warehouses", headers=headers).json()[0]

        supplier = client.post("/suppliers", headers=headers, json={"name": "مورد الاختبار"})
        assert supplier.status_code == 201, supplier.text
        customer = client.post("/customers", headers=headers, json={"name": "زبون الاختبار"})
        assert customer.status_code == 201, customer.text

        product = client.post("/products", headers=headers, json={
            "name": "إسمنت CEM II 42.5",
            "category": "الإسمنت",
            "base_unit": "كيس",
            "tracking_mode": "quantity",
            "purchase_price": "500",
            "sale_price": "600",
        })
        assert product.status_code == 201, product.text
        product_id = product.json()["id"]

        purchase = client.post("/purchases", headers=headers, json={
            "warehouse_id": warehouse["id"],
            "supplier_id": supplier.json()["id"],
            "invoice_number": "PUR-" + uuid4().hex[:12],
            "invoice_date": "2026-11-09",
            "lines": [{
                "product_id": product_id,
                "entered_quantity": "10",
                "entered_unit": "كيس",
                "base_quantity": "10",
                "unit_price": "500",
                "line_total": "5000",
            }],
            "discount": "0",
            "paid": "1000",
        })
        assert purchase.status_code == 201, purchase.text
        assert purchase.json()["due"] == "4000"

        sale = client.post("/sales", headers=headers, json={
            "warehouse_id": warehouse["id"],
            "customer_id": customer.json()["id"],
            "invoice_number": "SAL-" + uuid4().hex[:12],
            "lines": [{
                "product_id": product_id,
                "quantity": "4",
                "unit": "كيس",
                "unit_price": "600",
                "line_total": "2400",
            }],
            "discount": "0",
            "paid": "600",
        })
        assert sale.status_code == 201, sale.text
        assert sale.json()["due"] == "1800"

        stock = client.get("/stock", headers=headers)
        matching = [row for row in stock.json() if row["product_id"] == product_id]
        assert len(matching) == 1
        assert matching[0]["quantity"] == "6.000"

        oversell = client.post("/sales", headers=headers, json={
            "warehouse_id": warehouse["id"],
            "invoice_number": "SAL-" + uuid4().hex[:12],
            "lines": [{
                "product_id": product_id,
                "quantity": "7",
                "unit": "كيس",
                "unit_price": "600",
                "line_total": "4200",
            }],
        })
        assert oversell.status_code == 409

def test_rebar_purchase_converts_weight_to_piece_count_on_server(monkeypatch):
    monkeypatch.setenv("BATIPRO_TOKEN_SECRET", "test-token-secret-that-is-at-least-32-bytes")
    monkeypatch.setenv("BATIPRO_BOOTSTRAP_SECRET", "bootstrap-secret-for-integration-tests")
    email = f"steel-{uuid4().hex}@example.test"

    with TestClient(app) as client:
        registered = client.post("/auth/register", json={
            "email": email,
            "password": "Strong-test-password-123",
            "display_name": "Steel Owner",
            "organization_name": "Steel Store",
            "bootstrap_secret": "bootstrap-secret-for-integration-tests",
        })
        assert registered.status_code == 201, registered.text
        headers = {"Authorization": f"Bearer {registered.json()['access_token']}"}
        warehouse = client.get("/warehouses", headers=headers).json()[0]
        supplier = client.post("/suppliers", headers=headers, json={"name": "مورد الحديد"})
        product = client.post("/products", headers=headers, json={
            "name": "حديد T12",
            "category": "حديد تسليح T12",
            "base_unit": "قضيب",
            "tracking_mode": "piece",
            "piece_weight_kg": "10.656",
            "rebar_diameter_mm": "12",
            "bar_length_m": "12",
        })
        assert product.status_code == 201, product.text

        purchase = client.post("/purchases", headers=headers, json={
            "warehouse_id": warehouse["id"],
            "supplier_id": supplier.json()["id"],
            "invoice_number": "STEEL-" + uuid4().hex[:12],
            "invoice_date": "2026-11-09",
            "lines": [{
                "product_id": product.json()["id"],
                "entered_quantity": "106.56",
                "entered_unit": "kg",
                "base_quantity": "10",
                "unit_price": "1000",
                "line_total": "106560",
                "measured_weight_kg": "106.56",
            }],
        })
        assert purchase.status_code == 201, purchase.text
        stock = client.get("/stock", headers=headers).json()
        steel = [row for row in stock if row["product_id"] == product.json()["id"]]
        assert len(steel) == 1
        assert steel[0]["quantity"] == "10.000"

