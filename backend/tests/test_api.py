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
