from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from jarvis_api import integration_vault
from jarvis_api.config import settings
from jarvis_api.main import app

client = TestClient(app, base_url="https://testserver")


def test_postiz_and_artemis_secrets_are_encrypted_and_never_returned(tmp_path, monkeypatch):
    monkeypatch.setattr(integration_vault, "DB_PATH", tmp_path / "integration.sqlite3")
    key = Fernet.generate_key()
    monkeypatch.setattr(integration_vault, "_fernet", lambda: Fernet(key))
    monkeypatch.setattr(settings, "remote_gateway_token", "integration-admin-token")

    postiz_secret = "private-postiz-api-key"
    postiz = client.put(
        "/api/integration-config/postiz",
        headers={"X-Jarvis-Remote-Token": "integration-admin-token"},
        json={"base_url": "https://postiz.example/api/public/v1", "api_key": postiz_secret},
    )
    assert postiz.status_code == 200
    assert postiz_secret not in postiz.text

    artemis_secret = "private-artemis-gateway-token"
    google_secret = "private-google-gemini-key"
    artemis = client.put(
        "/api/integration-config/artemis",
        headers={"X-Jarvis-Remote-Token": "integration-admin-token"},
        json={"base_url": "http://127.0.0.1:8765", "gateway_token": artemis_secret, "google_api_key": google_secret},
    )
    assert artemis.status_code == 200
    assert artemis_secret not in artemis.text

    listed = client.get(
        "/api/integration-config",
        headers={"X-Jarvis-Remote-Token": "integration-admin-token"},
    )
    assert listed.status_code == 200
    assert listed.json()["postiz"]["configured"] is True
    assert listed.json()["artemis"]["configured"] is True
    assert postiz_secret not in listed.text
    assert artemis_secret not in listed.text
    assert google_secret not in listed.text

    assert integration_vault.get_integration_config("postiz")["api_key"] == postiz_secret
    assert integration_vault.get_integration_config("artemis")["gateway_token"] == artemis_secret
    assert integration_vault.get_integration_config("artemis")["google_api_key"] == google_secret


def test_integration_config_rejects_plain_http_public_host(monkeypatch):
    monkeypatch.setattr(settings, "remote_gateway_token", "integration-admin-token")
    response = client.put(
        "/api/integration-config/postiz",
        headers={"X-Jarvis-Remote-Token": "integration-admin-token"},
        json={"base_url": "http://postiz.example/api/v1", "api_key": "secret"},
    )
    assert response.status_code == 422
