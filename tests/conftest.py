"""Shared fixtures for the vault-secrets-demo test suite."""
import json
import os
import pathlib

import pytest

_INIT_FILE = pathlib.Path(".vault-init.json")


@pytest.fixture(scope="session")
def vault_creds() -> dict:
    """AppRole credentials for integration tests.

    Reads from VAULT_ROLE_ID / VAULT_SECRET_ID env vars (set by CI after
    init.sh runs), falling back to .vault-init.json for local dev.
    Skips the test if neither source is available.
    """
    addr = os.environ.get("VAULT_ADDR", "http://localhost:8200")
    role_id = os.environ.get("VAULT_ROLE_ID")
    secret_id = os.environ.get("VAULT_SECRET_ID")

    if not (role_id and secret_id) and _INIT_FILE.exists():
        data = json.loads(_INIT_FILE.read_text())
        role_id = role_id or data.get("role_id")
        secret_id = secret_id or data.get("secret_id")

    if not (role_id and secret_id):
        pytest.skip(
            "No Vault credentials available — run scripts/init.sh or set "
            "VAULT_ROLE_ID and VAULT_SECRET_ID environment variables."
        )

    return {"vault_addr": addr, "role_id": role_id, "secret_id": secret_id}
