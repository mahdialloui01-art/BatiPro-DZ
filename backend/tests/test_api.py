import os
from uuid import uuid4

import psycopg

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

        history = client.get("/sales", headers=headers)
        assert history.status_code == 200, history.text
        assert any(row["id"] == sale.json()["id"] for row in history.json())
        assert history.json()[0]["client"] == "Test Customer"

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

def test_read_only_role_and_membership_revocation_are_enforced(monkeypatch):
    monkeypatch.setenv("BATIPRO_TOKEN_SECRET", "test-token-secret-that-is-at-least-32-bytes")
    monkeypatch.setenv("BATIPRO_BOOTSTRAP_SECRET", "bootstrap-secret-for-integration-tests")
    email = f"viewer-{uuid4().hex}@example.test"

    with TestClient(app) as client:
        registered = client.post("/auth/register", json={
            "email": email,
            "password": "Strong-test-password-123",
            "display_name": "Viewer",
            "organization_name": "Viewer Store",
            "bootstrap_secret": "bootstrap-secret-for-integration-tests",
        })
        assert registered.status_code == 201
        token_data = registered.json()
        headers = {"Authorization": f"Bearer {token_data['access_token']}"}

        with psycopg.connect(os.environ["DATABASE_URL"]) as connection:
            connection.execute(
                "UPDATE organization_members SET role='viewer' WHERE user_id=%s AND organization_id=%s",
                (token_data["user_id"], token_data["organization_id"]),
            )

        profile = client.get("/me", headers=headers)
        assert profile.status_code == 200
        assert profile.json()["role"] == "viewer"

        denied = client.post("/products", headers=headers, json={
            "name": "محاولة إضافة",
            "category": "مواد البناء",
            "base_unit": "كيس",
        })
        assert denied.status_code == 403

        with psycopg.connect(os.environ["DATABASE_URL"]) as connection:
            connection.execute(
                "DELETE FROM organization_members WHERE user_id=%s AND organization_id=%s",
                (token_data["user_id"], token_data["organization_id"]),
            )

        revoked = client.get("/products", headers=headers)
        assert revoked.status_code == 401

def test_initial_snapshot_import_is_idempotent_and_does_not_replay_stock(monkeypatch):
    monkeypatch.setenv("BATIPRO_TOKEN_SECRET", "test-token-secret-that-is-at-least-32-bytes")
    monkeypatch.setenv("BATIPRO_BOOTSTRAP_SECRET", "bootstrap-secret-for-integration-tests")
    email = f"snapshot-{uuid4().hex}@example.test"

    with TestClient(app) as client:
        registered = client.post("/auth/register", json={
            "email": email,
            "password": "Strong-test-password-123",
            "display_name": "Snapshot Owner",
            "organization_name": "Snapshot Store",
            "bootstrap_secret": "bootstrap-secret-for-integration-tests",
        })
        assert registered.status_code == 201, registered.text
        headers = {"Authorization": f"Bearer {registered.json()['access_token']}"}

        payload = {
            "device_id": "windows-device-test-0001",
            "idempotency_key": "initial-snapshot-v1",
            "products": [{
                "local_id": "local-product-1",
                "name": "إسمنت الاختبار",
                "category": "الإسمنت",
                "unit": "كيس",
                "quantity": 8,
                "minimum_stock": 2,
                "purchase_price": 100,
                "sale_price": 130,
            }],
            "suppliers": [{"local_id": "local-supplier-1", "name": "مورد الاختبار"}],
            "customers": [{"local_id": "local-customer-1", "name": "زبون الاختبار"}],
            "purchases": [{
                "local_id": "legacy-purchase-1",
                "product_local_id": "local-product-1",
                "product": "إسمنت الاختبار",
                "supplier": "مورد الاختبار",
                "quantity": 10,
                "input_quantity": 10,
                "input_unit": "كيس",
                "stock_unit": "كيس",
                "unit_price": 100,
                "total": 1000,
                "paid": 500,
                "date": "2026-11-01T10:00:00",
            }],
            "sales": [{
                "local_id": "legacy-sale-1",
                "client": "زبون الاختبار",
                "total": 260,
                "paid": 130,
                "date": "2026-11-02T10:00:00",
                "items": [{
                    "productId": "local-product-1",
                    "name": "إسمنت الاختبار",
                    "unit": "كيس",
                    "quantity": 2,
                    "price": 130,
                    "total": 260,
                }],
            }],
        }

        first = client.post("/sync/initial-snapshot", headers=headers, json=payload)
        assert first.status_code == 200, first.text
        assert first.json()["counts"] == {
            "products": 1, "suppliers": 1, "customers": 1,
            "purchases": 1, "sales": 1, "opening_stock_items": 1,
        }
        id_map = first.json()["id_map"]
        assert id_map["products"]["local-product-1"]
        assert id_map["suppliers"]["local-supplier-1"]
        assert id_map["customers"]["local-customer-1"]
        assert id_map["purchases"]["legacy-purchase-1"]
        assert id_map["sales"]["legacy-sale-1"]

        repeated = client.post("/sync/initial-snapshot", headers=headers, json=payload)
        assert repeated.status_code == 200, repeated.text
        assert repeated.json()["already_imported"] is True

        stock = client.get("/stock", headers=headers)
        assert stock.status_code == 200
        assert len(stock.json()) == 1
        assert stock.json()[0]["quantity"] == "8.000"

        changed = {**payload, "products": [{**payload["products"][0], "quantity": 9}]}
        conflict = client.post("/sync/initial-snapshot", headers=headers, json=changed)
        assert conflict.status_code == 409

        second_device = {**payload, "device_id": "windows-device-test-0002"}
        second_import = client.post("/sync/initial-snapshot", headers=headers, json=second_device)
        assert second_import.status_code == 409



def test_continuous_sync_is_idempotent_conflict_safe_and_pullable(monkeypatch):
    monkeypatch.setenv("BATIPRO_TOKEN_SECRET", "test-token-secret-that-is-at-least-32-bytes")
    monkeypatch.setenv("BATIPRO_BOOTSTRAP_SECRET", "bootstrap-secret-for-integration-tests")
    with TestClient(app) as client:
        registered = client.post("/auth/register", json={
            "email": f"sync-{uuid4().hex}@example.test",
            "password": "Strong-test-password-123",
            "display_name": "Sync Owner",
            "organization_name": "Sync Store",
            "bootstrap_secret": "bootstrap-secret-for-integration-tests",
        })
        assert registered.status_code == 201, registered.text
        headers = {"Authorization": f"Bearer {registered.json()['access_token']}"}
        device_a = "device-a-" + uuid4().hex
        device_b = "device-b-" + uuid4().hex
        mutation_id = "mutation-" + uuid4().hex
        payload = {
            "device_id": device_a,
            "mutations": [{
                "mutation_id": mutation_id,
                "key": "batipro_products_v1",
                "value": '[{"id":"p1","name":"حديد T12"}]',
                "deleted": False,
                "base_revision": 0,
            }],
        }
        pushed = client.post("/sync/push", headers=headers, json=payload)
        assert pushed.status_code == 200, pushed.text
        result = pushed.json()
        assert result["has_conflicts"] is False
        assert result["accepted"][0]["revision"] == 1
        snapshot = client.get("/sync/snapshot", headers=headers)
        assert snapshot.status_code == 200, snapshot.text
        assert snapshot.json()["cursor"] == result["accepted"][0]["event_id"]
        assert snapshot.json()["documents"][0]["key"] == "batipro_products_v1"
        duplicate = client.post("/sync/push", headers=headers, json=payload)
        assert duplicate.status_code == 200, duplicate.text
        assert duplicate.json()["accepted"][0]["duplicate"] is True

        pull = client.get("/sync/pull", headers=headers, params={
            "after": 0, "limit": 100, "device_id": device_b,
        })
        assert pull.status_code == 200, pull.text
        changes = pull.json()["changes"]
        assert len(changes) == 1
        assert changes[0]["key"] == "batipro_products_v1"
        assert changes[0]["value"] == payload["mutations"][0]["value"]
        assert changes[0]["revision"] == 1

        conflict = client.post("/sync/push", headers=headers, json={
            "device_id": device_b,
            "mutations": [{
                "mutation_id": "conflict-" + uuid4().hex,
                "key": "batipro_products_v1",
                "value": "stale overwrite",
                "deleted": False,
                "base_revision": 0,
            }],
        })
        assert conflict.status_code == 200, conflict.text
        assert conflict.json()["has_conflicts"] is True
        assert conflict.json()["conflicts"][0]["server_revision"] == 1

        deleted = client.post("/sync/push", headers=headers, json={
            "device_id": device_b,
            "mutations": [{
                "mutation_id": "delete-" + uuid4().hex,
                "key": "batipro_products_v1",
                "value": None,
                "deleted": True,
                "base_revision": 1,
            }],
        })
        assert deleted.status_code == 200, deleted.text
        assert deleted.json()["has_conflicts"] is False
        after_delete = client.get("/sync/pull", headers=headers, params={
            "after": changes[0]["event_id"], "limit": 100, "device_id": device_a,
        })
        assert after_delete.status_code == 200
        assert after_delete.json()["changes"][0]["deleted"] is True

        forbidden_key = client.post("/sync/push", headers=headers, json={
            "device_id": device_a,
            "mutations": [{
                "mutation_id": "invalid-" + uuid4().hex,
                "key": "batipro_api_access_token",
                "value": "secret",
                "base_revision": 0,
            }],
        })
        assert forbidden_key.status_code == 422
