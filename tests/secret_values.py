"""Known placeholder secret values seeded by init.sh.

Imported by leakage tests and any other test that needs to assert
a specific value never appears in output or HTTP responses.
"""

KNOWN_SECRET_VALUES = {
    "db_password":       "demo-not-real-CHANGE-ME",
    "api_key":           "demo-fake-api-key-do-not-use-000111222",
    "connection_string": "postgresql://demo_user:demo-pass@localhost:5432/demo_db",
    "signing_key":       "demo-fake-jwt-signing-secret-xyz789",
    "webhook_url":       "https://hooks.example.invalid/services/DEMO/FAKE/0000",
}
