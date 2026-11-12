from fastapi.testclient import TestClient

from app.main import app


def test_liveness_endpoint():
    with TestClient(app) as client:
        response = client.get("/health/live")
    assert response.status_code == 200
    assert response.json() == {"status": "alive"}


def test_readiness_requires_database(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    with TestClient(app) as client:
        response = client.get("/health/ready")
    assert response.status_code == 503
