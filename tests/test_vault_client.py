"""Unit tests for VaultClient — hvac is fully mocked, no live Vault needed."""
import ast
import pathlib

import pytest

from vault_client import VaultAuthError, VaultClient, VaultSecretError


@pytest.fixture
def mock_hvac(mocker):
    mock_client = mocker.MagicMock()
    mocker.patch("vault_client.hvac.Client", return_value=mock_client)
    return mock_client


def _authenticated(mock_hvac) -> VaultClient:
    mock_hvac.is_authenticated.return_value = True
    client = VaultClient("http://vault:8200", "test-role-id", "test-secret-id")
    client.login()
    return client


class TestLogin:
    def test_success(self, mock_hvac):
        mock_hvac.is_authenticated.return_value = True
        VaultClient("http://vault:8200", "role", "secret").login()

    def test_wrong_credentials_raises_vault_auth_error(self, mock_hvac):
        mock_hvac.auth.approle.login.side_effect = Exception("invalid role or secret id")
        with pytest.raises(VaultAuthError):
            VaultClient("http://vault:8200", "role", "bad-secret").login()

    def test_unauthenticated_response_raises_vault_auth_error(self, mock_hvac):
        mock_hvac.is_authenticated.return_value = False
        with pytest.raises(VaultAuthError):
            VaultClient("http://vault:8200", "role", "secret").login()


class TestGetSecret:
    def test_kv_pair_shape(self, mock_hvac):
        """demo-db: two fields (username + password)."""
        mock_hvac.secrets.kv.v2.read_secret_version.return_value = {
            "data": {"data": {"username": "demo_user", "password": "demo-not-real-CHANGE-ME"}}
        }
        secret = _authenticated(mock_hvac).get_secret("demo-db")
        assert secret == {"username": "demo_user", "password": "demo-not-real-CHANGE-ME"}

    def test_single_string_shape(self, mock_hvac):
        """demo-api-key / demo-signing-key / demo-webhook: single 'value' field."""
        mock_hvac.secrets.kv.v2.read_secret_version.return_value = {
            "data": {"data": {"value": "demo-fake-api-key-do-not-use-000111222"}}
        }
        secret = _authenticated(mock_hvac).get_secret("demo-api-key")
        assert secret == {"value": "demo-fake-api-key-do-not-use-000111222"}

    def test_connection_string_shape(self, mock_hvac):
        """demo-connection-string: structured URL-shaped value."""
        mock_hvac.secrets.kv.v2.read_secret_version.return_value = {
            "data": {"data": {"value": "postgresql://demo_user:demo-pass@localhost:5432/demo_db"}}
        }
        secret = _authenticated(mock_hvac).get_secret("demo-connection-string")
        assert secret["value"].startswith("postgresql://")

    def test_fetch_error_raises_vault_secret_error(self, mock_hvac):
        mock_hvac.secrets.kv.v2.read_secret_version.side_effect = Exception("permission denied")
        with pytest.raises(VaultSecretError):
            _authenticated(mock_hvac).get_secret("demo-db")

    def test_get_secret_before_login_raises_vault_auth_error(self):
        with pytest.raises(VaultAuthError):
            VaultClient("http://vault:8200", "role", "secret").get_secret("demo-db")


def test_no_print_or_logging_in_vault_client():
    """vault_client.py must never call print() or logging.* with any value."""
    source = (
        pathlib.Path(__file__).parent.parent / "consumer-app" / "vault_client.py"
    ).read_text()
    tree = ast.parse(source)
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name) and func.id == "print":
            pytest.fail("vault_client.py contains a print() call")
        if isinstance(func, ast.Attribute) and func.attr in {
            "debug", "info", "warning", "error", "critical", "exception",
        }:
            pytest.fail(f"vault_client.py contains a logging call: .{func.attr}()")
