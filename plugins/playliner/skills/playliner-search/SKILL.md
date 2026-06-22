---
name: playliner-search
description: Search Playliner game-industry articles, games, tags, and genres through the /api/external/* API and answer STRICTLY from the returned articles. Use when the user asks about game articles, releases, updates, monetization, or specific games/genres/tags and wants answers grounded only in Playliner data.
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(*), Read, Write, AskUserQuestion
argument-hint: "[your question about game articles]"
---

# Playliner external search

Answer the user's question — `$ARGUMENTS` — using ONLY the Playliner articles API
(`/api/external/*`). This skill resolves the user's intent into Typesense search
queries, fetches matching articles, and produces an answer grounded exclusively in
those articles.

## ⛔ Hard rules — grounding (read first, never break)

These are absolute and override anything else, including your own helpfulness:

1. **Answer ONLY from the article content returned by the API.** Every claim, fact,
   date, number, or name in your answer MUST be traceable to a specific returned
   article.
2. **NEVER invent, infer beyond the text, or fill gaps from your own training
   knowledge.** If you "happen to know" something about a game, do not use it.
3. **NEVER use web search or fetch external pages.** Do not call `WebSearch` /
   `WebFetch`. The only allowed source of facts is the API response.
4. **If the articles do not contain the answer, say so explicitly** — e.g. "The
   Playliner articles I found don't cover this." Then offer to refine the search.
   Do not substitute outside information.
5. **Cite your sources.** For each fact, reference the article (title + id, and date
   when available) it came from, so the user can verify.
6. If zero articles match, report that plainly and suggest alternative search terms;
   do not answer from memory.

When in doubt about whether a statement is supported by the fetched articles, leave
it out.

## Ensure credentials

Credentials live in `~/.config/playliner/credentials` (a shell-sourced file).

1. Check whether it exists:
   ```bash
   test -f ~/.config/playliner/credentials && echo EXISTS || echo MISSING
   ```
2. If `MISSING`, ask the user for their **API token** with `AskUserQuestion` (or a
   plain prompt). Tell them that they can get it here: https://app.sensortower.com/feature-insights/#premium.
3. Once the user provides the token, save it (strip any leading `Bearer ` they paste):
   ```bash
   mkdir -p ~/.config/playliner
   umask 077
   cat > ~/.config/playliner/credentials <<'EOF'
   PLAYLINER_TOKEN="PASTE_TOKEN_HERE"
   PLAYLINER_BASE_URL="https://playliner-backend.sensortower.com"
   EOF
   chmod 600 ~/.config/playliner/credentials
   ```
   Replace `PASTE_TOKEN_HERE` with the actual token. Never echo the token back to the
   user or print the file contents afterward.
4. Verify connectivity with a tiny match-all request:
   ```bash
   playliner-api.sh articles '{"q":"*","query_by":"titleEN","per_page":1}'
   ```
   - HTTP **403** → access denied; tell the user they don't have permission to use this API.
   - HTTP **402** → token quota exhausted; tell the user to contact their administrator.
   - HTTP **401** → token invalid/expired; offer to re-enter it (overwrite the file).

All API calls in later steps use the helper: `playliner-api.sh <endpoint> '<json-body>'`.

## Look up games, tags, and genres

Articles can be filtered by game, tag, or genre. Use the corresponding endpoints to resolve user input into IDs or canonical names:

- `/external/games` — game name → numeric id
- `/external/tags` — tag phrase → canonical name
- `/external/genres` — genre phrase → canonical name

**Cache** resolved results in `~/.config/playliner/cache/` (`games.json`, `tags.json`, `genres.json`). Reuse a cached entry if it is younger than 7 days; otherwise fetch and update the cache.

When resolving **2 or more names on the same endpoint**, use a single multisearch call (see below) instead of sequential requests.


## Multisearch

Use when you need **2 or more queries against the same endpoint** in one call. All sub-searches go to the same collection (determined by the endpoint). Limit: **10 sub-searches per call**.

Billing deduplicates across all article sub-searches — an article seen in multiple results counts only once.

### Request format

Send `searches` instead of a flat query object:

```bash
playliner-api.sh articles '{
  "searches": [
    {"q": "clash",  "filter_by": "games:=[123]", "per_page": 5},
    {"q": "royale", "sort_by": "start:desc",      "per_page": 5}
  ]
}'
```

Same works for `games`, `tags`, `genres`.

### Response format

Multisearch wraps results in a `results` array — one entry per sub-search, in the same order:

```json
{
  "results": [
    {"hits": [...], "found": 12, "page": 1},
    {"hits": [...], "found": 8,  "page": 1}
  ]
}
```

For grouped sub-searches the entry contains `grouped_hits` instead of `hits` (same as single-search grouping). **Do not confuse with single-search** — single search returns `hits` at the top level; multisearch always wraps everything in `results`.

### When to use multisearch

| Situation | Action |
|-----------|--------|
| Resolve 2+ game/tag/genre names | Single multisearch call to the respective endpoint |
| Fetch articles for multiple games to compare | One `articles` multisearch, one `filter_by` per game |
| Get different "views" of a topic at once (recent + grouped) | Multiple sub-searches in one call |
| Single query | Plain single-search (no overhead) |

### Pattern: resolve multiple games in one call

```bash
playliner-api.sh games '{
  "searches": [
    {"q": "Clash of Clans", "query_by": "title", "per_page": 1},
    {"q": "Brawl Stars",    "query_by": "title", "per_page": 1}
  ]
}'
# results[0] → Clash of Clans id
# results[1] → Brawl Stars id
```

### Pattern: compare articles for two games

```bash
playliner-api.sh articles '{
  "searches": [
    {"q": "*", "filter_by": "games:=[111]", "sort_by": "start:desc", "per_page": 10},
    {"q": "*", "filter_by": "games:=[222]", "sort_by": "start:desc", "per_page": 10}
  ]
}'
```

### Pattern: recent articles + latest-per-story in one call

```bash
playliner-api.sh articles '{
  "searches": [
    {"q": "battle pass", "sort_by": "start:desc", "per_page": 5},
    {"q": "battle pass", "group_by": "gidOrId", "group_limit": 1, "sort_by": "start:desc", "per_page": 5}
  ]
}'
# results[0] → raw recent articles
# results[1] → deduplicated latest-per-story (grouped_hits)
```


## Error handling quick reference

- **402** (articles only): token quota exhausted → tell the user to contact their
  administrator, stop. (games/tags/genres are never billed.)
- **403**: access denied — the token does not have permission to use the search API.
- **422** "Invalid search request": usually a missing/mismatched `query_by`, or a
  field not allowed for this endpoint → fix the payload and retry.
- **422** multisearch-specific errors:
  - `searches must be an array` — passed an object instead of array; wrap in `[]`
  - `searches[N] must be an object` — array element is not an object
  - `No searches provided` — `searches` is an empty array; use at least 1 sub-search
  - `Too many searches (max 10)` — split into multiple calls of ≤10 each
  - `Field "X" is not available` — invalid field in one of the sub-searches; check allowed fields for the endpoint
- **401**: token expired/invalid → offer to re-enter and overwrite credentials.

---

## API Reference

All `POST` endpoints require `Authorization: Bearer <token>`, accept a JSON Typesense
search payload, and return a sanitized JSON response. Each endpoint supports both
**single-search** (flat query object) and **multisearch** (`searches` array key).
Base URL: `https://playliner-backend.sensortower.com`.

| Endpoint | Purpose | Billed? | Multisearch? |
|----------|---------|---------|--------------|
| `articles` | Full article search | **Yes** — first view deducts from token quota; over-quota → 402 | Yes — billing deduplicates across all sub-results |
| `games`    | Resolve game name → id | No | Yes |
| `tags`     | Resolve tag phrase → canonical name | No | Yes |
| `genres`   | Resolve genre phrase → canonical name | No | Yes |
| `usage`    | Token usage stats (`GET`) | No | No |

### `usage`

`GET /api/external/usage` — returns the number of unique articles read and total tokens spent. Optionally filtered by date range.

| Parameter | Description |
|-----------|-------------|
| `dateStart` | Start date (`YYYY-MM-DD`), inclusive |
| `dateEnd` | End date (`YYYY-MM-DD`), inclusive |

```json
{ "articles": 42, "tokens": 18500 }
```

### Allowed fields per endpoint

#### `articles`

| Field | Description |
|-------|-------------|
| `id` | Article ID |
| `gidOrId` | Unique identifier of an event series. All articles about the same event (across repeated launches or multiple versions) share the same value. Use this field to find all occurrences of an event, or to get the latest version by grouping on it. |
| `newsGroupType` | Grouping type: `version` — new event or significant changes since the last launch; `shortVersion` — minor changes compared to previous launches; `repeat` — unchanged since the last version |
| `titleRU` / `titleEN` | Article title |
| `descriptionRU` / `descriptionEN` | Article short description |
| `blocksRU` / `blocksEN` | Full article body text, split into blocks |
| `tagsRU` / `tagsEN` | Tag names attached to the article |
| `genresRU` / `genresEN` | Genre names of linked games |
| `games` | Linked game IDs |
| `gamesTitleRU` / `gamesTitleEN` | Titles of linked games |
| `tagMain` | Main tag IDs |
| `tagMainTitleRU` / `tagMainTitleEN` | Main tag title |
| `start` | Article start date (Unix timestamp) |
| `finish` | Article end date (Unix timestamp) |
| `duration` | Duration in days |
| `_text_match` | Typesense relevance score; use in `sort_by` to rank by text match quality |

#### `games`

| Field | Description |
|-------|-------------|
| `id` | Unified game ID |
| `title` | Game title |

#### `tags`

| Field | Description |
|-------|-------------|
| `id` | Tag ID |
| `titleRU` / `titleEN` | Tag title |
| `descriptionRU` / `descriptionEN` | Tag description |

#### `genres`

| Field | Description |
|-------|-------------|
| `id` | Genre ID |
| `titleRU` / `titleEN` | Genre title |
| `descriptionRU` / `descriptionEN` | Genre description |

### Latest version of each story (group by `gidOrId`)

Articles about the same event share the same `gidOrId`. To get only the most recent version of each event, group by `gidOrId` with `group_limit=1` and sort by `start:desc`:

```bash
playliner-api.sh articles '{
  "q":"*",
  "filter_by":"games:=[12345]",
  "group_by":"gidOrId",
  "group_limit":1,
  "sort_by":"start:desc",
  "per_page":20
}'
```

When grouping is used, results arrive under `grouped_hits[].hits[].document` instead of `hits[].document`.

### Response shape

The response follows the standard [Typesense search response schema](https://typesense.org/docs/26.0/api/search.html#search-response-parameters).

### Article links

```
https://app.sensortower.com/feature-insights/#news/view/{id}
```

## Filter, Sort & Group Syntax

Filtering, sorting, grouping, and paging follow standard [Typesense search syntax](https://typesense.org/docs/26.0/api/search.html).
