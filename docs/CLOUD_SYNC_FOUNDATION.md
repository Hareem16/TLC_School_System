# TLC School System — Cloud Sync Foundation

## What has been prepared

The live Supabase project has an additive cloud-sync foundation:

- Existing school, membership, and registered-device records are preserved.
- `school_sync_records` stores versioned school records with tombstones.
- `school_sync_receipts` makes client change submissions idempotent.
- `tlc_sync_push` accepts bounded batches, checks active membership and approved device, enforces role permissions, and detects stale revisions.
- `tlc_sync_pull` returns ordered changes after a server cursor.
- A private `tlc-school-backups` Storage bucket exists. Backup files must be encrypted on the client before upload.
- Anonymous execution was revoked from the existing school helper functions.
- Sync RPCs require an authenticated user, active school membership, and an approved device.
- Sync payloads are limited to 1 MiB and recursively reject credential/token field names, including nested password hashes and refresh tokens.
- The F.D.O. role is limited to fee and inventory sync; financial reversals are Admin-only.

## Current live status

- One school: The Learning Circle Secondary School.
- One active owner membership.
- One approved Windows device.
- No school operational records have been uploaded to the sync tables.
- No cloud backup files have been uploaded.

## Important implementation boundary

This is the **server foundation**, not yet an activated end-to-end app sync. The Flutter client still needs its local SQLite outbox, change-capture triggers, safe pull-apply logic, conflict UI, cloud account linking, and membership/device approval screens.

The current ZIP uses local SQLite schema version 18; GitHub `main` was found at version 14. Do not replace version 18 files with the older branch. Reconcile the current source snapshot before integrating client code.

## Security rules

- Never upload `user_accounts.password_salt`, `user_accounts.password_hash`, `account_requests.password_salt`, or `account_requests.password_hash`.
- Never put Supabase service-role/secret keys in Flutter or GitHub.
- Keep local login available offline; cloud sign-in is a separate identity/session.
- Require an active school membership and approved device before sync.
- Fee receipts and reversals are append-only. The cloud push function rejects their update/delete operations.
- Reversals are restricted to cloud owner/admin roles. F.D.O. can sync fee and inventory records, not reversals.
- Teacher, parent, and student cloud sync remains disabled until class/subject/student scopes are implemented server-side.
- Do not treat GitHub as a database or backup location.

## Deployment notes

The migrations in this directory reproduce the migrations applied to the live Supabase project on 2026-11-14. The live project also has a fourth helper-permissions migration that keeps the recursive payload-check helpers callable only by the database function owner. If a fresh Supabase project is used, apply them in timestamp order after the existing school, membership, and device foundation migrations. Do not re-run them blindly against a database that already has these versions.

## Next client-side steps

1. Reconcile GitHub main with the current version 18 source.
2. Add SQLite outbox/state/conflict tables and change-capture triggers.
3. Add cloud email identity linking without replacing local offline login.
4. Add membership and device approval workflows for newly linked accounts/devices.
5. Implement bounded push/pull, conflict handling, and initial baseline upload.
6. Add encrypted cloud backup upload/restore and test recovery.
7. Run Windows and Android offline/multi-device tests before enabling automatic sync.
