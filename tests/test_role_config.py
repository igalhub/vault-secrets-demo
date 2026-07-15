"""Vault-side role configuration: demo-app's secret_id_ttl must stay finite (VSD-011)."""
import json
import os
import pathlib

import hvac
import pytest

_INIT_FILE = pathlib.Path(".vault-init.json")


@pytest.fixture(scope="session")
def root_token() -> str:
    """Root token for reading role config — not covered by demo-app-policy.

    Only ever read from the gitignored .vault-init.json, never an env var,
    so it can never end up in CI logs or masked output.
    """
    if not _INIT_FILE.exists():
        pytest.skip(
            "No .vault-init.json available — run scripts/init.sh to read role config."
        )
    return json.loads(_INIT_FILE.read_text())["root_token"]


def test_demo_app_secret_id_ttl_is_finite(root_token):
    addr = os.environ.get("VAULT_ADDR", "http://localhost:8200")
    client = hvac.Client(url=addr, token=root_token)
    role = client.auth.approle.read_role("demo-app")
    ttl = role["data"]["secret_id_ttl"]
    assert 0 < ttl <= 60 * 60 * 24 * 365
