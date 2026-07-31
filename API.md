# Playliner External API

Plain HTTP reference for the Playliner search and analytics API — the same API the
`playliner-search` skill uses under the hood.

## Base URL

```
https://app.sensortower.com/playliner/api
```

All endpoints live under `/v1/external/` and are **`POST`-only** with a JSON body.

## Authentication

Send your Playliner API token as a bearer token:

```
Authorization: Bearer <YOUR_API_TOKEN>
```

Get the token on the [API settings page](https://app.sensortower.com/users/edit/api-settings).

## Request shape

Every call looks the same — `POST`, JSON in, JSON out:

```bash
curl -sS -X POST https://app.sensortower.com/playliner/api/v1/external/articles \
  -H "Authorization: Bearer $PLAYLINER_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"q":"battle pass","query_by":"titleEN","per_page":5}'
```

The four search endpoints (`articles`, `games`, `tags`, `genres`) take a
[Typesense search payload](https://typesense.org/docs/26.0/api/search.html);
`analytics` takes its own filter payload.

## Endpoints

| Endpoint | Method + path | Purpose | Multisearch |
|----------|---------------|---------|-------------|
| `articles`  | `POST /v1/external/articles`  | Full article search | Yes |
| `games`     | `POST /v1/external/games`     | Resolve game name → numeric id | Yes |
| `tags`      | `POST /v1/external/tags`      | Resolve tag phrase → canonical name | Yes |
| `genres`    | `POST /v1/external/genres`    | Resolve genre phrase → canonical name | Yes |
| `analytics` | `POST /v1/external/analytics` | Event performance analytics table | No |

---

## Search endpoints

### Common parameters

Standard Typesense search parameters apply. The ones you will actually use:

| Parameter | Type | Description |
|-----------|------|-------------|
| `q` | string | Search phrase. `*` matches everything |
| `query_by` | string | Comma-separated fields to search in. Required unless `q` is `*` — a missing or mismatched `query_by` is the usual cause of a 422 |
| `filter_by` | string | Filter expression, e.g. `games:=[12345]`, `start:>1700000000` |
| `sort_by` | string | e.g. `start:desc`, `_text_match:desc` |
| `group_by` / `group_limit` | string / int | Collapse results, e.g. `gidOrId` + `1` |
| `page` / `per_page` | int | Paging |

Full syntax for `filter_by`, `sort_by`, and grouping: the
[Typesense search docs](https://typesense.org/docs/26.0/api/search.html).

### Response

Search endpoints return the standard
[Typesense search response](https://typesense.org/docs/26.0/api/search.html#search-response-parameters):

```json
{
  "found": 42,
  "page": 1,
  "hits": [
    { "document": { "id": "...", "titleEN": "...", "start": 1712345678 } }
  ]
}
```

When `group_by` is used, results arrive under `grouped_hits[].hits[].document`
instead of `hits[].document`.

### Fields — `articles`

| Field | Description |
|-------|-------------|
| `id` | Article ID |
| `gidOrId` | Identifier of an event series — all articles about the same event (repeated launches, multiple versions) share this value |
| `titleEN` | Article title |
| `descriptionEN` | Short description |
| `blocksEN` | Full article body, split into blocks; media URLs (`.jpg`, `.mp4`) appear inline as separate array elements |
| `tagsEN` | Tag names attached to the article |
| `genresEN` | Genre names of linked games |
| `games` | Linked game IDs |
| `gamesTitleEN` | Titles of linked games |
| `tagMain` / `tagMainTitleEN` | Main tag ID / title |
| `start` / `finish` | Start and end date (Unix timestamp) |
| `duration` | Duration in days |

### Fields — `games`

| Field | Description |
|-------|-------------|
| `id` | Unified game ID |
| `title` | Game title |

### Fields — `tags` and `genres`

| Field | Description |
|-------|-------------|
| `id` | Tag / genre ID |
| `titleEN` | Title |
| `descriptionEN` | Description |

### Article links

Build a UI link to any article from its `id`:

```
https://app.sensortower.com/playliner/#news/view/{id}
```

### Examples

Resolve a game name to its id:

```bash
curl -sS -X POST https://app.sensortower.com/playliner/api/v1/external/games \
  -H "Authorization: Bearer $PLAYLINER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"q":"Clash of Clans","query_by":"title","per_page":1}'
```

Latest articles for that game:

```bash
curl -sS -X POST https://app.sensortower.com/playliner/api/v1/external/articles \
  -H "Authorization: Bearer $PLAYLINER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"q":"*","filter_by":"games:=[12345]","sort_by":"start:desc","per_page":20}'
```

Only the most recent version of each event (deduplicate repeated launches by
grouping on `gidOrId`):

```bash
curl -sS -X POST https://app.sensortower.com/playliner/api/v1/external/articles \
  -H "Authorization: Bearer $PLAYLINER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "q":"*",
        "filter_by":"games:=[12345]",
        "group_by":"gidOrId",
        "group_limit":1,
        "sort_by":"start:desc",
        "per_page":20
      }'
```

---

## Multisearch

The four search endpoints accept several queries in one request. Send a `searches`
array instead of a flat query object — all sub-searches run against that endpoint's
collection. **Maximum 10 sub-searches per call.**

```bash
curl -sS -X POST https://app.sensortower.com/playliner/api/v1/external/games \
  -H "Authorization: Bearer $PLAYLINER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "searches": [
          {"q":"Clash of Clans","query_by":"title","per_page":1},
          {"q":"Brawl Stars","query_by":"title","per_page":1}
        ]
      }'
```

The response wraps everything in a `results` array — one entry per sub-search, in
the same order:

```json
{
  "results": [
    {"hits": [], "found": 12, "page": 1},
    {"hits": [], "found": 8,  "page": 1}
  ]
}
```

Note the difference: a single search returns `hits` at the top level, multisearch
always nests under `results`. Grouped sub-searches carry `grouped_hits` instead of
`hits`, same as in single search.

---

## `analytics` — event performance

`POST /v1/external/analytics` returns the event analytics table: one row per event,
with launch history and per-metric impact percentages. There is **no pagination** —
the whole matching table comes back at once, so narrow the filters for large games
or genres. Multisearch is not supported.

```bash
curl -sS -X POST https://app.sensortower.com/playliner/api/v1/external/analytics \
  -H "Authorization: Bearer $PLAYLINER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"filters":{"games":[12345],"keywords":"battle pass"},"lang":"en"}'
```

### Request body

All parameters are optional — `{}` returns the table with default filters.

| Parameter | Type | Description |
|-----------|------|-------------|
| `filters.games` | int[] | Unified game IDs (resolve names via the `games` endpoint) |
| `filters.tags` | int[] | Tag IDs (resolve via `tags`) |
| `filters.genres` | int[] | Genre IDs (resolve via `genres`) |
| `filters.keywords` | string | Substring match against event titles |
| `lang` | string | Language of `title` — use `en` |

### Response

Rows arrive in a `{"success": true, "data": [...]}` envelope. Empty values are
omitted from a row — treat an absent field as "no recorded uptrend", not as `0`.

| Column | Meaning |
|--------|---------|
| `id` | Article ID of the event (link: `https://app.sensortower.com/playliner/#news/view/{id}`) |
| `title` | Event title |
| `game` | Title of the linked game |
| `dateFirst` / `dateLast` | First and most recent launch (`YYYY-MM-DD`) |
| `repetitionCount` | How many times the event has run |
| `durationMin` / `durationMax` / `durationAvg` | Shortest / longest / average launch duration, in days |
| `impactfulLaunches` | % of launches that coincided with a revenue uptrend |
| `releaseRevenueImpact` | Revenue trend of the very first launch, in % |
| `revenueImpact` | % of launches with a revenue uptrend |
| `downloadsImpact` | % of launches with a downloads uptrend |
| `dauImpact` | % of launches with a DAU uptrend |
| `timeSpentImpact` | % of launches with a time-spent uptrend |
| `totalTimeSpentImpact` | % of launches with a total-time-spent uptrend |
| `sessionDurationImpact` | % of launches with a session-duration uptrend |
| `avgTimeSpentImpact` | % of launches with an average-time-spent uptrend |
| `avgSessionCountImpact` | % of launches with an average-session-count uptrend |

**Access-dependent columns.** `revenueImpact` and `downloadsImpact` are always
included. Every other impact metric requires the corresponding module to be enabled
for the account; columns without access are silently absent from every row. If a
metric is missing from *all* rows, the account most likely lacks access to it —
that is not the same as "no impact".

---

## Errors

| Status | Meaning | What to do |
|--------|---------|------------|
| `401` | Token invalid or expired | Re-issue the token on the API settings page |
| `402` | Article view limit reached (`articles` only) | Contact your account administrator |
| `403` | Access denied — the token lacks permission for the external API, or for the analytics module | Contact your account administrator |
| `422` | Validation error in the payload | See below |

Common `422` causes:

- `Invalid search request` — usually a missing or mismatched `query_by`, or a field
  that is not allowed for this endpoint.
- `searches must be an array` — `searches` was an object; wrap it in `[]`.
- `searches[N] must be an object` — an array element is not an object.
- `No searches provided` — `searches` is empty; send at least one sub-search.
- `Too many searches (max 10)` — split into several calls of ≤10.
- `Field "X" is not available` — invalid field for this endpoint; check the field
  tables above.
