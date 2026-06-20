import hashlib
import hmac
import os
import sqlite3
import urllib.parse
from contextlib import asynccontextmanager

from fastapi import FastAPI

from vault_client import VaultAuthError, VaultClient, VaultSecretError

_VAULT_ADDR = os.environ.get("VAULT_ADDR", "http://vault:8200")
_VAULT_ROLE_ID = os.environ.get("VAULT_ROLE_ID", "")
_VAULT_SECRET_ID = os.environ.get("VAULT_SECRET_ID", "")

_status: dict[str, str] = {
    "vault_auth": "pending",
    "demo_db": "pending",
    "demo_api_key": "pending",
    "demo_connection_string": "pending",
    "demo_signing_key": "pending",
    "demo_webhook": "pending",
}


def _use_demo_db(secret: dict) -> None:
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE demo (user TEXT)")
    conn.execute("INSERT INTO demo VALUES (?)", (secret["username"],))
    conn.close()
    _status["demo_db"] = "ok"


def _use_demo_api_key(secret: dict) -> None:
    if not secret.get("value"):
        raise ValueError("API key is empty")
    _status["demo_api_key"] = "ok"


def _use_demo_connection_string(secret: dict) -> None:
    parsed = urllib.parse.urlparse(secret["value"])
    if not all([parsed.scheme, parsed.hostname, parsed.path]):
        raise ValueError("connection string is not a valid URL")
    _status["demo_connection_string"] = "ok"


def _use_demo_signing_key(secret: dict) -> None:
    hmac.new(secret["value"].encode(), b"demo-payload", hashlib.sha256).digest()
    _status["demo_signing_key"] = "ok"


def _use_demo_webhook(secret: dict) -> None:
    parsed = urllib.parse.urlparse(secret["value"])
    if not all([parsed.scheme, parsed.netloc]):
        raise ValueError("webhook is not a valid URL")
    _status["demo_webhook"] = "ok"


_SECRETS = [
    ("demo-db",                _use_demo_db,                "demo_db"),
    ("demo-api-key",           _use_demo_api_key,           "demo_api_key"),
    ("demo-connection-string", _use_demo_connection_string, "demo_connection_string"),
    ("demo-signing-key",       _use_demo_signing_key,       "demo_signing_key"),
    ("demo-webhook",           _use_demo_webhook,           "demo_webhook"),
]


def _bootstrap() -> None:
    client = VaultClient(_VAULT_ADDR, _VAULT_ROLE_ID, _VAULT_SECRET_ID)
    try:
        client.login()
    except VaultAuthError as exc:
        _status["vault_auth"] = f"failed: {type(exc).__name__}"
        return
    _status["vault_auth"] = "ok"

    for path, use_fn, key in _SECRETS:
        try:
            use_fn(client.get_secret(path))
        except (VaultSecretError, Exception) as exc:
            _status[key] = f"failed: {type(exc).__name__}"


@asynccontextmanager
async def lifespan(_: FastAPI):
    _bootstrap()
    yield


app = FastAPI(lifespan=lifespan)


@app.get("/status")
def status() -> dict:
    return _status
