import hvac


class VaultAuthError(Exception):
    pass


class VaultSecretError(Exception):
    pass


class VaultClient:
    def __init__(self, url: str, role_id: str, secret_id: str) -> None:
        self._url = url
        self._role_id = role_id
        self._secret_id = secret_id
        self._client: hvac.Client | None = None

    def login(self) -> None:
        client = hvac.Client(url=self._url)
        try:
            client.auth.approle.login(
                role_id=self._role_id,
                secret_id=self._secret_id,
            )
        except Exception as exc:
            raise VaultAuthError(f"AppRole login failed: {type(exc).__name__}") from exc
        if not client.is_authenticated():
            raise VaultAuthError("AppRole login did not yield an authenticated token")
        self._client = client

    def get_secret(self, path: str) -> dict:
        if self._client is None:
            raise VaultAuthError("Not authenticated — call login() first")
        try:
            response = self._client.secrets.kv.v2.read_secret_version(
                path=path,
                mount_point="secret",
                raise_on_deleted_version=True,
            )
        except Exception as exc:
            raise VaultSecretError(f"Failed to read '{path}': {type(exc).__name__}") from exc
        return response["data"]["data"]
