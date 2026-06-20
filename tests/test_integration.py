"""Full-stack integration: real Vault, all five secrets, /status returns all ok."""
import main
import pytest
from fastapi.testclient import TestClient


@pytest.fixture(autouse=True)
def reset_status():
    for k in list(main._status):
        main._status[k] = "pending"


@pytest.fixture()
def live_app(vault_creds, mocker):
    mocker.patch.object(main, "_VAULT_ADDR",      vault_creds["vault_addr"])
    mocker.patch.object(main, "_VAULT_ROLE_ID",   vault_creds["role_id"])
    mocker.patch.object(main, "_VAULT_SECRET_ID", vault_creds["secret_id"])
    with TestClient(main.app) as client:
        yield client


def test_vault_auth_ok(live_app):
    assert live_app.get("/status").json()["vault_auth"] == "ok"


def test_demo_db_ok(live_app):
    assert live_app.get("/status").json()["demo_db"] == "ok"


def test_demo_api_key_ok(live_app):
    assert live_app.get("/status").json()["demo_api_key"] == "ok"


def test_demo_connection_string_ok(live_app):
    assert live_app.get("/status").json()["demo_connection_string"] == "ok"


def test_demo_signing_key_ok(live_app):
    assert live_app.get("/status").json()["demo_signing_key"] == "ok"


def test_demo_webhook_ok(live_app):
    assert live_app.get("/status").json()["demo_webhook"] == "ok"
