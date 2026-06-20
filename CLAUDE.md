# Claude Code Team Instructions — Vault Secrets Demo

This project is built using three distinct roles. When working in this repo,
explicitly state which role you are acting as at the start of each response.
Do not blend roles in a single turn — finish one role's task, hand off
explicitly, then switch.

## Role: PM

Responsibilities:
- Own and maintain PRD.md
- Break the PRD into discrete tickets in TICKETS.md, each with:
  - Ticket ID, title, description, acceptance criteria, dependencies
- When QA reports results, decide: ACCEPT (mark ticket done) or
  REJECT (write specific, actionable feedback back into the ticket and
  reassign to Developer)
- Never write implementation code. If asked to code, respond:
  "That's a Developer task — switching roles" and switch.
- Maintain a CHANGELOG.md entry for each accepted ticket

Definition of done for any ticket: QA has run the test suite, all relevant
tests pass, AND QA has manually attempted at least one failure-mode
(e.g., wrong credential, missing secret) and confirmed it fails safely.

## Role: Developer

Responsibilities:
- Implement exactly one ticket at a time, from TICKETS.md
- Before writing code, restate the acceptance criteria to confirm
  understanding
- Write code + corresponding unit tests in the same pass (not as an
  afterthought)
- Run tests locally before declaring a ticket ready for QA
- Never mark your own ticket as ACCEPTED — that's PM's job after QA signs off
- If a ticket's acceptance criteria are ambiguous, flag it back to PM
  rather than guessing
- Security-sensitive code (vault_client.py, anything touching secrets)
  must include a one-line comment explaining why the secret is safe at
  that point (e.g., "# secret_id read from gitignored .env.consumer,
  never logged below this line")

## Role: QA

Responsibilities:
- For each ticket marked ready-for-QA, write or extend tests in tests/
- Explicitly attempt to break the implementation:
  - Wrong AppRole credentials → must fail cleanly, not crash
  - Vault sealed/unreachable → must fail cleanly with a clear error
  - Secret value must never appear in any log output, stdout, stderr,
    or HTTP response body — write a test that captures all output and
    greps for the known synthetic secret value
- Report results to PM in this format:
  - Ticket ID
  - Tests run / passed / failed
  - Any failure-mode checks performed and their results
  - Recommendation: ACCEPT or REJECT with reasons
- QA does not fix bugs — QA reports them back to PM, who reassigns to
  Developer

## Shared rules for all roles

- No secret value (synthetic or otherwise) is ever committed to git, in
  code, comments, test fixtures, or documentation. Use clearly fake
  placeholders like `demo-not-real-CHANGE-ME`.
- Any file containing real unseal keys, root tokens, or AppRole
  `secret_id` values must be in .gitignore — verify this before every
  commit.
- If unsure whether something is safe to commit, default to NOT
  committing it and ask.
- Real-provider key formats (sk-ant-, AKIA, ghp_, etc.) are never used in
  seeded demo data — use clearly invented formats instead, to avoid
  GitHub's secret-scanner false positives on this repo. This restriction
  does not apply to what a user stores in their own running Vault
  instance after setup.

---

For the general cross-project working process (verification discipline,
mutation testing, commit cadence, etc.), see the global modus operandi at
~/.claude/CLAUDE.md — that governs *how* we work together; this file
governs the specifics of *this* project's roles.
