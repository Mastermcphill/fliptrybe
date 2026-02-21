# Meilisearch Production Runbook (Render)

## Required durability settings
- Use a Render `pserv` for Meilisearch with a persistent disk mount at `/meili_data`.
- Start with `20GB` disk for `tri-o-meili` (increase when `databaseSize` reaches ~70% of disk).
- Set `MEILI_DB_PATH=/meili_data` so index data survives deploys/restarts.
- Keep `MEILI_ENV=production`.
- `MEILI_MASTER_KEY` must be set in production. The Meili Docker CMD now exits early if it is missing.

## Snapshot / backup strategy
- Enable scheduled snapshots:
  - `MEILI_SCHEDULE_SNAPSHOT=true`
  - `MEILI_SNAPSHOT_INTERVAL_SEC=86400` (daily)
- Snapshots live on the same disk unless copied off-host. For disaster recovery, regularly copy snapshot artifacts to external storage.
- Keep at least one verified restore point before major schema/index migrations.

## Safe MEILI_MASTER_KEY rotation
1. Generate a new strong key.
2. Set the new key in Render for all services that call Meili (`web`, `worker`, `tri-o-meili`) during a maintenance window.
3. Redeploy Meili first, then web/worker.
4. Verify with `GET /api/admin/search/status` as admin:
   - `health.reachable=true`
   - `engine=meili`
5. Remove old key copies from local shells/CI secrets.

## Validate persistence after redeploy
1. Note baseline before redeploy from `GET /api/admin/search/status`:
   - `index_exists`
   - `document_count`
   - `databaseSize`
   - `lastUpdate`
2. Redeploy `tri-o-meili`.
3. Re-run `GET /api/admin/search/status` and confirm:
   - same `index_uid` and non-zero `document_count`
   - `databaseSize` did not reset to 0
   - search reads still work (`GET /api/listings/search?...`)
4. If data is missing, stop writes and restore from latest snapshot.

## Quick production checks
- Initialize index settings safely: `POST /api/admin/search/init`
- Reindex jobs: `POST /api/admin/search/reindex`
- Dependency health: `GET /api/admin/ops/health-deps`
- Worker/broker visibility: `GET /api/admin/ops/celery/status`
