---
name: playliner-search
description: Search Playliner game-industry articles, games, tags, and genres through the /api/v1/external/* API and answer STRICTLY from the returned articles. Use when the user asks about game articles, releases, updates, monetization, event performance/impact analytics (revenue, downloads, DAU uptrends), or specific games/genres/tags and wants answers grounded only in Playliner data.
user-invocable: true
allowed-tools: Bash(*), Read, Write, AskUserQuestion
argument-hint: "[your question about game articles]"
---

# Playliner external search

Answer the user's question using ONLY the Playliner articles API
(`/api/v1/external/*`). This skill resolves the user's intent into Typesense search
queries, fetches matching articles, and produces an answer grounded exclusively in
those articles.

The question: `$ARGUMENTS`

(If the line above is empty or still shows the literal placeholder `$ARGUMENTS`,
take the question from the user's most recent message instead.)

## ⛔ Hard rules — grounding (read first, never break)

These are absolute and override anything else, including your own helpfulness:

1. **Answer ONLY from the article content returned by the API.** Every claim, fact,
   date, number, or name in your answer MUST be traceable to a specific returned
   article.
2. **NEVER invent, infer beyond the text, or fill gaps from your own training
   knowledge.** If you "happen to know" something about a game, do not use it.
3. **NEVER use web search or fetch external pages.** Do not use any web-search,
   browsing, or URL-fetching tool available in your environment (e.g. `WebSearch`,
   `WebFetch`, browser tools, `curl` to non-Playliner hosts). The only allowed
   source of facts is the API response.
4. **If the articles do not contain the answer, say so explicitly** — e.g. "The
   Playliner articles I found don't cover this." Then offer to refine the search.
   Do not substitute outside information.
5. **Cite your sources.** Every fact must reference the article it came from so the user
   can verify, formatted as a markdown link (see **Formatting rules** for the exact format).
6. If zero articles match, report that plainly and suggest alternative search terms;
   do not answer from memory.
7. **Never expose technical/provenance details in the final answer** (data source, API,
   games/genres/tags IDs, traceability notes) — they may be used while reasoning, but the user-facing answer must stay clean.

When in doubt about whether a statement is supported by the fetched articles, leave
it out.

## Formatting rules

1. **Attach images as often as possible.** Media links live right inside
   `blocksEN`, in the correct order together with the text — each is a
   separate array element (`.jpg` for images, `.mp4` for videos). Weave relevant images
   into the answer to visualize the text as much as possible. Render images with the alt text left empty (`![](url)`); render videos as a
   link `[▶ caption](url)`.
2. **Put the caption below the image, never inside the markdown tag.** Example:
   ```
   ![](link)
   description
   ```
3. **Format links correctly.** Cite an article as a markdown link whose clickable text is
   the article/game/tag/genre title or another short, relevant phrase —
   `[title](https://app.sensortower.com/playliner/#news/view/{articleId})`.

## Locate the helper script

All API calls use the bundled helper `scripts/playliner-api.sh`, which lives inside
**this skill's directory** (the directory containing this SKILL.md). It is NOT on
`PATH`. Resolve its absolute path **once**, store it in a shell variable, and reuse
that variable for every call. Try in order, stopping at the first path that exists:

```bash
# (1) if the environment provides the plugin root (e.g. Claude Code):
PLAYLINER_API="$CLAUDE_PLUGIN_ROOT/skills/playliner-search/scripts/playliner-api.sh"

# (2) otherwise, if you know where this SKILL.md is (you just read it),
#     the script sits next to it:
PLAYLINER_API="<directory of this SKILL.md>/scripts/playliner-api.sh"

# (3) otherwise, search the standard skill locations of all platforms first
#     (installed copies win over anything in the current folder):
PLAYLINER_API=$(find ~/.agents ~/.codex ~/.cursor ~/.claude -type f \
  -path '*playliner-search/scripts/playliner-api.sh' 2>/dev/null | head -1)
# only if still not found, look under the current folder (e.g. a local clone):
[ -n "$PLAYLINER_API" ] || PLAYLINER_API=$(find . -maxdepth 8 -type f \
  -path '*playliner-search/scripts/playliner-api.sh' 2>/dev/null | head -1)
```

Verify your candidate with `test -f "$PLAYLINER_API"` before using it. Every example
below invokes the helper as `"$PLAYLINER_API"` — always substitute the resolved
variable, never call the bare name `playliner-api.sh` (run `bash "$PLAYLINER_API" …`
if the file is not executable).

## Ensure credentials

Credentials live in `~/.config/playliner/credentials` (a shell-sourced file).

1. Check whether it exists:
   ```bash
   test -f ~/.config/playliner/credentials && echo EXISTS || echo MISSING
   ```
2. If `MISSING`, ask the user for their **API token** and stop until they reply —
   use a dedicated question tool if your environment has one (e.g. `AskUserQuestion`),
   otherwise just ask in a plain message. Tell them that they can find it here: https://app.sensortower.com/users/edit/api-settings.
3. Once the user provides the token, save it:
   ```bash
   mkdir -p ~/.config/playliner
   umask 077
   cat > ~/.config/playliner/credentials <<'EOF'
   PLAYLINER_TOKEN="PASTE_TOKEN_HERE"
   PLAYLINER_BASE_URL="https://app.sensortower.com/playliner/api"
   EOF
   chmod 600 ~/.config/playliner/credentials
   ```
   Replace `PASTE_TOKEN_HERE` with the actual token. Never echo the token back to the
   user or print the file contents afterward.
4. Verify connectivity with a tiny match-all request:
   ```bash
   "$PLAYLINER_API" articles '{"q":"*","query_by":"titleEN","per_page":1}'
   ```
   - HTTP **403** → access denied; tell the user they don't have permission to use this API.
   - HTTP **402** → article view limit reached; tell the user to contact their administrator.
   - HTTP **401** → token invalid/expired; offer to re-enter it (overwrite the file).

All API calls in later steps use the helper: `"$PLAYLINER_API" <endpoint> '<json-body>'`
(the variable resolved in **Locate the helper script**).

## Look up games, tags, and genres

Articles can be filtered by game, tag, or genre. Use the corresponding endpoints to resolve user input into IDs or canonical names:

- `/v1/external/games` — game name → numeric id
- `/v1/external/tags` — tag phrase → canonical name
- `/v1/external/genres` — genre phrase → canonical name

**Cache** resolved results in `~/.config/playliner/cache/` (`games.json`, `tags.json`, `genres.json`). Reuse a cached entry if it is younger than 7 days; otherwise fetch and update the cache.

When resolving **2 or more names on the same endpoint**, use a single multisearch call (see below) instead of sequential requests.


## Multisearch

Use when you need **2 or more queries against the same endpoint** in one call. All sub-searches go to the same collection (determined by the endpoint). Limit: **10 sub-searches per call**.

### Request format

Send `searches` instead of a flat query object:

```bash
"$PLAYLINER_API" articles '{
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
"$PLAYLINER_API" games '{
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
"$PLAYLINER_API" articles '{
  "searches": [
    {"q": "*", "filter_by": "games:=[111]", "sort_by": "start:desc", "per_page": 10},
    {"q": "*", "filter_by": "games:=[222]", "sort_by": "start:desc", "per_page": 10}
  ]
}'
```

### Pattern: recent articles + latest-per-story in one call

```bash
"$PLAYLINER_API" articles '{
  "searches": [
    {"q": "battle pass", "sort_by": "start:desc", "per_page": 5},
    {"q": "battle pass", "group_by": "gidOrId", "group_limit": 1, "sort_by": "start:desc", "per_page": 5}
  ]
}'
# results[0] → raw recent articles
# results[1] → deduplicated latest-per-story (grouped_hits)
```


## Error handling quick reference

- **402** (articles only): article view limit reached → tell the user to contact their
  administrator, stop.
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

All `POST` endpoints authenticate with the user's **API token** and return a sanitized
JSON response. The search endpoints (`articles`, `games`, `tags`, `genres`) accept a
JSON Typesense search payload and support both **single-search** (flat query object)
and **multisearch** (`searches` array key); `analytics` uses its own filter payload.
Base URL: `https://app.sensortower.com/playliner/api`.

| Endpoint | Purpose | Multisearch? |
|----------|---------|--------------|
| `articles` | Full article search | Yes |
| `games`    | Resolve game name → id | Yes |
| `tags`     | Resolve tag phrase → canonical name | Yes |
| `genres`   | Resolve genre phrase → canonical name | Yes |
| `analytics` | Event performance analytics table | No |

### `analytics` — event performance analytics

`POST /api/v1/external/analytics` — the event analytics table. Use it when you need
to see **how events perform** based on revenue uptrend, downloads, DAU and other
impact metrics: one row per event, with launch history and per-metric impact
percentages.

No pagination — the whole matching table comes back
in one response, so narrow the filters for large games/genres. No multisearch.

```bash
"$PLAYLINER_API" analytics '{
  "filters": {
    "games": [12345],
    "keywords": "battle pass"
  },
  "lang": "en"
}'
```

#### Request body

All parameters are optional — `{}` returns the table with default filters.

| Parameter | Type | Description |
|-----------|------|-------------|
| `filters.games` | int[] | Unified game IDs — resolve names via `games` endpoint. Default: empty (no filter) |
| `filters.tags` | int[] | Tag IDs — resolve via `tags` endpoint. Default: empty |
| `filters.genres` | int[] | Genre IDs — resolve via `genres` endpoint. Default: empty |
| `filters.keywords` | string | Substring match against event titles |
| `lang` | string | Language of `title`. Use `en` |

#### Response

Rows arrive in the standard `{"success": true, "data": [...]}` envelope, one row per
event. Empty values are omitted from a row — treat absence as "no recorded uptrend",
not as a hard 0.

| Column | Meaning |
|--------|---------|
| `id` | Article ID of the event. Article link: `https://app.sensortower.com/playliner/#news/view/{id}` |
| `title` | Event title |
| `game` | Title of the linked game |
| `dateFirst` / `dateLast` | Dates of the first and most recent launch (`YYYY-MM-DD`) |
| `repetitionCount` | How many times the event has run |
| `durationMin` / `durationMax` / `durationAvg` | Shortest / longest / average launch duration, in days |
| `impactfulLaunches` | % of the event's launches that coincided with a revenue uptrend |
| `releaseRevenueImpact` | Revenue trend of the event's very first launch, in % |
| `revenueImpact` | % of launches with a revenue uptrend |
| `downloadsImpact` | % of launches with a downloads uptrend |
| `dauImpact` | % of launches with a daily-active-users uptrend |
| `timeSpentImpact` | % of launches with a time-spent uptrend |
| `totalTimeSpentImpact` | % of launches with a total-time-spent uptrend |
| `sessionDurationImpact` | % of launches with a session-duration uptrend |
| `avgTimeSpentImpact` | % of launches with an average-time-spent uptrend |
| `avgSessionCountImpact` | % of launches with an average-session-count uptrend |

#### Access-dependent columns

**Some metric columns may be unavailable due to insufficient account permissions.**
`revenueImpact` and `downloadsImpact` are always included; the other impact metrics
(`dauImpact`, `timeSpentImpact`, `totalTimeSpentImpact`, `sessionDurationImpact`,
`avgTimeSpentImpact`, `avgSessionCountImpact`) each require the corresponding metric
module to be enabled for the account, and columns without access are silently absent
from every row. If a metric the user asks about is missing from **all** rows, the
account likely lacks access to it — say so and suggest contacting the administrator;
never present it as "no impact".

#### Errors

- **401** — token expired/invalid.
- **403** — access denied: the token lacks permission for the external API or the analytics table module.
- **422** — validation error in the request payload.

### Allowed fields per endpoint

#### `articles`

| Field | Description |
|-------|-------------|
| `id` | Article ID |
| `gidOrId` | Unique identifier of an event series. All articles about the same event (across repeated launches or multiple versions) share the same value. Use this field to find all occurrences of an event, or to get the latest version by grouping on it. |
| `newsGroupType` | Grouping type: `version` — new event or significant changes since the last launch; `shortVersion` — minor changes compared to previous launches; `repeat` — unchanged since the last version |
| `titleEN` | Article title |
| `descriptionEN` | Article short description |
| `blocksEN` | Full article body text, split into blocks |
| `tagsEN` | Tag names attached to the article |
| `genresEN` | Genre names of linked games |
| `games` | Linked game IDs |
| `gamesTitleEN` | Titles of linked games |
| `tagMain` | Main tag IDs |
| `tagMainTitleEN` | Main tag title |
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
| `titleEN` | Tag title |
| `descriptionEN` | Tag description |

#### `genres`

| Field | Description |
|-------|-------------|
| `id` | Genre ID |
| `titleEN` | Genre title |
| `descriptionEN` | Genre description |

### Latest version of each story (group by `gidOrId`)

Articles about the same event share the same `gidOrId`. To get only the most recent version of each event, group by `gidOrId` with `group_limit=1` and sort by `start:desc`:

```bash
"$PLAYLINER_API" articles '{
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
https://app.sensortower.com/playliner/#news/view/{id}
```

## Filter, Sort & Group Syntax

Filtering, sorting, grouping, and paging follow standard [Typesense search syntax](https://typesense.org/docs/26.0/api/search.html).
