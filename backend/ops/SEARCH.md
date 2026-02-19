# FlipTrybe Search (Meilisearch)

## Overview
FlipTrybe supports dual search modes:
- `SEARCH_ENGINE=meili`: `/api/listings/search` uses Meilisearch.
- Any other value: `/api/listings/search` uses SQL (`search_v2_service`).

If Meilisearch is enabled but unavailable, SQL fallback is controlled by `SEARCH_FALLBACK_SQL`.

## Environment Variables
- `SEARCH_ENGINE` default: `""` (SQL mode)
- `MEILI_HOST` e.g. `http://tri-o-meili:7700`
- `MEILI_API_KEY` optional API key
- `SEARCH_TIMEOUT_MS` default: `1500`
- `SEARCH_INDEX_LISTINGS` default: `listings_v1`
- `SEARCH_FALLBACK_SQL` default: `true`

Render service defaults are in `backend/render.yaml`.

## Index Initialization
Admin-only endpoint:
- `POST /api/admin/search/init`

This endpoint:
- verifies Meilisearch health
- ensures the listings index exists
- applies index settings (filterable/sortable/searchable attributes)

## Reindex / Backfill
Admin-only endpoint:
- `POST /api/admin/search/reindex`

Optional payload:
```json
{
  "batch_size": 500,
  "since_id": 0
}
```

Response contains:
- `task_id`
- `estimated_batches`
- `total_candidates`

The endpoint enqueues Celery task `search_reindex_all`.

## Async Indexing Tasks
Listing writes enqueue Celery tasks after DB commit:
- create/update/approve/inspection flag: `search_index_listing(listing_id)`
- delete/deactivate path: `search_delete_listing(listing_id)`

Task guarantees:
- idempotent upserts by document id
- retry with exponential backoff (`max_retries=5`)
- safe replay for duplicate tasks

## Filter Mapping (`/api/listings/search`)
Supported query params map to Meili filters:
- taxonomy: `category`, `category_id`, `parent_category_id`, `brand_id`, `model_id`
- vehicle: `listing_type`, `make`, `model`, `year`
- energy: `battery_type`, `inverter_capacity`, `lithium_only`
- real estate: `property_type`, `bedrooms_min/max`, `bathrooms_min/max`, `furnished`, `serviced`, `land_size_min/max`, `title_document_type`
- location: `state`, `city`, `area`
- trust/ops: `delivery_available`, `inspection_required`, `status`, `condition`
- price: `min_price`, `max_price`

Sort mapping:
- `price_low|price_low_to_high|priceasc` -> `price_asc`
- `price_high|price_high_to_low|pricedesc` -> `price_desc`
- `new|latest` -> `newest`
- default -> `relevance`

## Fallback and Timeouts
- Meili calls are timeout-bound by `SEARCH_TIMEOUT_MS`.
- On Meili error/timeout:
  - if `SEARCH_FALLBACK_SQL=true`, API falls back to SQL path.
  - else API returns `503` with `SEARCH_UNAVAILABLE` and `trace_id`.

## Operational Notes
- Meili data persists at `/meili_data` in Render private service `tri-o-meili`.
- Search caches use existing cache layer (`v1:feed:*` keys).
- Listing updates trigger cache invalidation and search task enqueue.
- Admin `/api/listings/search` requests that include inactive records still use SQL path to preserve behavior.
