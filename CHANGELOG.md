# Changelog

## VSD-011: AppRole `secret_id` given a finite TTL

`secret_id_ttl` for the `demo-app` AppRole is now 90 days (was `0` — never
expires), matching the README's TTL claim. The `approle` auth mount's
default 32-day `max_lease_ttl` is tuned up to 90 days in `scripts/init.sh`
so the role's configured TTL actually takes effect on issued `secret_id`s.
Added `tests/test_role_config.py` to guard against a regression back to
`secret_id_ttl=0`.
