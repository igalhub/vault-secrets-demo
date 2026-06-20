"""Wrong credentials → clean degraded response, no crash, no stack trace leak."""
import main
import pytest
from fastapi.testclient import TestClient
from vault_client import VaultAuthError


@pytest.fixture(autouse=True)
def reset_status():
    for k in list(main._status):
        main._status[k] = "pending"


def test_wrong_secret_id_returns_200_not_500(mocker):
    mocker.patch("main.VaultClient.login", side_effect=VaultAuthError("bad secret_id"))
    with TestClient(main.app) as client:
        response = client.get("/status")
    assert response.status_code == 200


def test_vault_auth_shows_failed(mocker):
    mocker.patch("main.VaultClient.login", side_effect=VaultAuthError("bad secret_id"))
    with TestClient(main.app) as client:
        response = client.get("/status")
    assert response.json()["vault_auth"].startswith("failed:")


def test_secrets_stay_pending_on_auth_failure(mocker):
    mocker.patch("main.VaultClient.login", side_effect=VaultAuthError("bad secret_id"))
    with TestClient(main.app) as client:
        response = client.get("/status")
    data = response.json()
    for key in ["demo_db", "demo_api_key", "demo_connection_string", "demo_signing_key", "demo_webhook"]:
        assert data[key] == "pending", f"expected pending, got {data[key]!r} for {key}"


def test_no_traceback_in_response_on_auth_failure(mocker):
    mocker.patch("main.VaultClient.login", side_effect=VaultAuthError("bad secret_id"))
    with TestClient(main.app) as client:
        response = client.get("/status")
    assert "Traceback" not in response.text
    assert "traceback" not in response.text
