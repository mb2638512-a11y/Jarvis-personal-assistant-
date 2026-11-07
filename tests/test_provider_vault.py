from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from jarvis_api import provider_vault
from jarvis_api.config import settings
from jarvis_api.main import app

client = TestClient(app)


def test_provider_vault_encrypts_credentials_and_never_returns_them(tmp_path, monkeypatch):
    monkeypatch.setattr(provider_vault, "DB_PATH", tmp_path / "providers.sqlite3")
    monkeypatch.setattr(provider_vault, "KEY_PATH", tmp_path / "provider.key")
    monkeypatch.setattr(settings, "provider_vault_key", Fernet.generate_key().decode())
    monkeypatch.setattr(settings, "remote_gateway_token", "test-admin-token")

    secret = "never-return-this-provider-key"
    created = client.post(
        "/api/models/providers",
        headers={"X-Jarvis-Remote-Token": "test-admin-token"},
        json={
            "name": "Test provider",
            "base_url": "https://provider.example/v1",
            "model": "test-model",
            "api_key": secret,
        },
    )
    assert created.status_code == 200
    assert secret not in created.text
    provider_id = created.json()["provider"]["id"]

    listed = client.get(
        "/api/models/providers",
        headers={"X-Jarvis-Remote-Token": "test-admin-token"},
    )
    assert listed.status_code == 200
    assert secret not in listed.text
    assert listed.json()["credentials_exposed"] is False

    active = provider_vault.active_provider()
    assert active is not None
    assert active["api_key"] == secret
    assert active["model"] == "test-model"

    deleted = client.delete(
        f"/api/models/providers/{provider_id}",
        headers={"X-Jarvis-Remote-Token": "test-admin-token"},
    )
    assert deleted.status_code == 200
    assert provider_vault.active_provider() is None


def test_provider_vault_rejects_non_https_remote_provider_url():
    response = client.post(
        "/api/models/providers",
        headers={"X-Jarvis-Remote-Token": "test-admin-token"},
        json={
            "name": "Unsafe",
            "base_url": "http://provider.example/v1",
            "model": "test-model",
            "api_key": "secret",
        },
    )
    assert response.status_code == 422


def test_shared_catalog_requires_a_paired_device_token(monkeypatch):
    monkeypatch.setattr(settings, "remote_gateway_token", "test-admin-token")
    response = client.get("/api/models/providers/catalog")
    assert response.status_code == 401
    assert "credentials_exposed" not in response.text
