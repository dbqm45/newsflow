#!/usr/bin/env bash
# Waliduje migrację + seed + test dymny na lokalnym PostgreSQL 16 z pgvector.
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${DB:-newsflow_test}
PSQL=${PSQL:-"psql -v ON_ERROR_STOP=1 -q"}
dropdb --if-exists "$DB"; createdb "$DB"
$PSQL -d "$DB" -f supabase/tests/00_supabase_stub.sql
for f in supabase/migrations/*.sql; do echo "-> $f"; $PSQL -d "$DB" -f "$f"; done
$PSQL -d "$DB" -f supabase/seed.sql
$PSQL -d "$DB" -f supabase/seed.sql   # idempotentność
$PSQL -d "$DB" -f supabase/tests/10_smoke_test.sql
