"""No secret value may appear in stdout, stderr, or any HTTP response body."""
import main
import pytest
from fastapi.testclient import TestClient

from secret_values import KNOWN_SECRET_VALUES


@pytest.fixture(autouse=True)
def reset_status():
    for k in list(main._status):
        main._status[k] = "pending"


@pytest.fixture()
def full_run(vault_creds, mocker, capsys):
    mocker.patch.object(main, "_VAULT_ADDR",      vault_creds["vault_addr"])
    mocker.patch.object(main, "_VAULT_ROLE_ID",   vault_creds["role_id"])
    mocker.patch.object(main, "_VAULT_SECRET_ID", vault_creds["secret_id"])
    with TestClient(main.app) as client:
        response = client.get("/status")
    captured = capsys.readouterr()
    all_output = captured.out + captured.err + response.text
    return all_output


def test_db_password_not_leaked(full_run):
    assert KNOWN_SECRET_VALUES["db_password"] not in full_run, \
        "DB password appeared in stdout, stderr, or HTTP response"


def test_api_key_not_leaked(full_run):
    assert KNOWN_SECRET_VALUES["api_key"] not in full_run, \
        "API key appeared in stdout, stderr, or HTTP response"


def test_connection_string_not_leaked(full_run):
    assert KNOWN_SECRET_VALUES["connection_string"] not in full_run, \
        "Connection string appeared in stdout, stderr, or HTTP response"


def test_signing_key_not_leaked(full_run):
    assert KNOWN_SECRET_VALUES["signing_key"] not in full_run, \
        "Signing key appeared in stdout, stderr, or HTTP response"


def test_webhook_url_not_leaked(full_run):
    assert KNOWN_SECRET_VALUES["webhook_url"] not in full_run, \
        "Webhook URL appeared in stdout, stderr, or HTTP response"
