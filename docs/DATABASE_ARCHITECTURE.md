# BatiPro DZ database architecture

## Target

- PostgreSQL 16 is the authoritative shared database on the server.
- Flutter on Android and Windows keeps a local SQLite database for offline use.
- Flutter clients communicate with PostgreSQL only through the authenticated HTTPS API.
- The API owns validation, authorization, transaction boundaries, idempotency and audit logging.

## Initial relational model

The first migration creates organizations and memberships, users and roles, warehouses, categories, products, suppliers, customers, purchase and sales invoices with lines, stock movements, payments, sync request idempotency records, and audit logs.

Amounts use fixed-precision NUMERIC columns rather than floating-point database types. Inventory changes are represented as signed stock movements. Rebar products can retain diameter, bar length and per-piece weight so kilogram/ton purchases can be converted into piece counts without losing the measured weight.

## Offline synchronization contract

1. Each client operation is committed locally with a stable UUID and an outbox entry in the same SQLite transaction.
2. The client sends queued operations over HTTPS with a device ID and idempotency key.
3. The API validates organization membership and payloads, then commits invoice headers, lines, stock movements, payments and sync result atomically.
4. Repeated delivery of the same key returns the saved result instead of applying stock twice.
5. The client marks an outbox item synced only after receiving the committed server result.
6. Conflicts are explicit; the client must not silently overwrite a newer server record.

## Safe rollout

- Keep existing SQLite and legacy SharedPreferences data intact.
- Do not switch the app to remote-only operation.
- Deploy PostgreSQL with backups and TLS before configuring production clients.
- Add authentication and role enforcement before exposing business endpoints.
- Migrate existing records with a dry-run, row counts and reconciliation report before any production import.

## Current implementation boundary

This foundation adds the initial schema, container setup, migration command and health endpoints. It does not yet expose sales/purchase CRUD, authentication, or client synchronization. Those must be implemented and tested before the desktop/mobile apps are configured to use a live server.
