---
name: playliner-search
description: Search Playliner game-industry news, games, tags, and genres through the /api/external/* API and answer STRICTLY from the returned articles. Use when the user asks about game news, releases, updates, monetization, or specific games/genres/tags and wants answers grounded only in Playliner data.
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(*), Read, Write, AskUserQuestion
argument-hint: "[your question about game news]"
---

# Playliner external search

Answer the user's question — `$ARGUMENTS` — using ONLY the Playliner news API
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

## Step 1 — Ensure credentials exist

Credentials live in `~/.config/playliner/credentials` (a shell-sourced file).

1. Check whether it exists:
   ```bash
   test -f ~/.config/playliner/credentials && echo EXISTS || echo MISSING
   ```
2. If `MISSING`, ask the user for their **Bearer token** with `AskUserQuestion` (or a
   plain prompt). Tell them it is a Bearer token for the Playliner API and will be
   stored locally with `0600` permissions, outside the git repo.
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

## Step 2 — Resolve the question into IDs / names (hybrid cache)

The user speaks in natural language ("новости по Clash of Clans", "mobile RPG
updates"). Turn that into precise filters.

**Filtering model (important):**
- **By game** → use the numeric game **id**. Get it from `/external/games`, then
  filter articles with `games:=[<id>]`.
- **By tag** → filter articles by the tag's **localized name** against `tagsEN` /
  `tagsRU` (these are string arrays). Use `/external/tags` to turn the user's fuzzy
  phrase into the exact canonical tag name.
- **By genre** → same as tags, but against `genresEN` / `genresRU`, resolved via
  `/external/genres`.

(The numeric `tags`/`genres` id arrays are NOT queryable on the articles endpoint —
only names are. Game ids ARE queryable.)

**Hybrid cache** (avoid re-resolving the same phrase every time):
- Cache dir: `~/.config/playliner/cache/`. Use one file per type:
  `games.json`, `tags.json`, `genres.json`, each an object of
  `{ "<lowercased query>": <api result>, "_fetched_at": <unix> }`.
- Before hitting the network, check the cache file for the lowercased phrase and use
  the hit if `_fetched_at` is younger than **7 days**.
- On a **miss or stale** entry, fall back to an on-demand search against the matching
  endpoint, then write the result back into the cache file.
- If a cache file is missing/corrupt, just treat it as a miss.

Resolving examples:
```bash
# game name -> id
playliner-api.sh games \
  '{"q":"clash of clans","query_by":"title","per_page":5}'

# tag phrase -> canonical name(s)
playliner-api.sh tags \
  '{"q":"update","query_by":"titleEN,titleRU","per_page":5}'

# genre phrase -> canonical name(s)
playliner-api.sh genres \
  '{"q":"strategy","query_by":"titleEN,titleRU","per_page":5}'
```
If several candidates match and the choice is ambiguous (e.g. multiple games named
similarly), use `AskUserQuestion` to let the user pick before querying articles.

## Step 3 — Query the articles

Endpoint: `articles`. **`query_by` is required** whenever `q` is a real term (not
`"*"`); otherwise the API returns 422. Recommended default `query_by` for free-text:
`titleRU,titleEN,blocksRU,blocksEN,descriptionRU,descriptionEN`.

Free-text search:
```bash
playliner-api.sh articles '{
  "q":"loot box monetization",
  "query_by":"titleRU,titleEN,blocksRU,blocksEN,descriptionRU,descriptionEN",
  "per_page":20,
  "sort_by":"_text_match:desc"
}'
```

Filtered by a resolved game id, newest first:
```bash
playliner-api.sh articles '{
  "q":"*",
  "filter_by":"games:=[12345]",
  "sort_by":"start:desc",
  "per_page":20
}'
```

### Latest version of each story (group by `gidOrId`)

Articles are grouped by event or story. For example, a recurring in-game event like
"Lava Quest" may appear many times in the index — each occurrence is a separate
article, but they all share the same `gidOrId` value because they belong to the same
event group. Some of these articles are identical re-posts; others have small updates.

Without grouping, a search for "Lava Quest" will return all occurrences as separate
hits, flooding the results with near-duplicate content. To get only the **most recent
version of each event**, group by `gidOrId` with `group_limit=1` and sort by
`start:desc`:

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
When grouping is used the results arrive under `grouped_hits[].hits[].document`
instead of `hits[].document` — read accordingly (see API Reference below).

For filter and sort syntax, see the **Filter & Sort Syntax** section below.
For the full field list and response shape, see the **API Reference** section below.

## Step 4 — Read the articles and answer

1. Parse the JSON. Collect documents from `hits[].document` (or
   `grouped_hits[].hits[].document` when grouped).
2. The article text is in `blocksRU` / `blocksEN` (full-text body), `titleRU/EN`,
   `descriptionRU/EN`. `start` is the publish time (unix seconds).
3. Build the answer **only** from these fields. Prefer the locale matching the user's
   language; fall back to the other locale if the preferred one is empty.
4. Cite each fact: article title + link + date from `start`. The permanent link format is:
   `https://app.sensortower.com/feature-insights/#news/view/{id}`
5. After each search, check `filter_by` in the response — it shows the filter actually
   used. If it differs from what you intended, adjust the next query. Also check
   `unknown_params`: if non-empty, a parameter was silently dropped (likely a typo).
6. If the fetched set is thin or off-topic, refine the query (broaden/narrow filters,
   try other locales' fields, raise `per_page`) and search again before concluding.
7. If, after reasonable refinement, the articles still don't answer the question, say
   so per the Hard rules — never fill the gap from outside knowledge.

## Error handling quick reference

- **402** (articles only): token quota exhausted → tell the user to contact their
  administrator, stop. (games/tags/genres are never billed.)
- **403**: access denied — the token does not have permission to use the search API.
- **422** "Invalid search request": usually a missing/mismatched `query_by`, or a
  field not allowed for this endpoint → fix the payload and retry.
- **401**: token expired/invalid → offer to re-enter and overwrite credentials.

---

## API Reference

All endpoints are `POST`, require `Authorization: Bearer <token>`, accept a JSON
Typesense search payload, and return a sanitized JSON response.
Base URL: `https://playliner-backend.sensortower.com`.

| Endpoint | Purpose | Billed? |
|----------|---------|---------|
| `articles` | Full news search | **Yes** — first view deducts from token quota; over-quota → 402 |
| `games`    | Resolve game name → id | No |
| `tags`     | Resolve tag phrase → canonical name | No |
| `genres`   | Resolve genre phrase → canonical name | No |

### Accepted search parameters (all endpoints)

`q`, `query_by`, `query_by_weights`, `filter_by`, `sort_by`, `page`, `per_page`,
`group_by`, `group_limit`, `include_fields`, `limit_hits`.

- `q`: query string. `"*"` = match all. Anything else **requires** `query_by`.
- `per_page`: default 20, clamped to **1..250**.
- `page`: clamped to **1..10000**.
- For `articles`, scope to a section: `sections:=[1]` (Overviews) or `sections:=[59]` (Updates).

### Allowed fields per endpoint

#### `articles`
- `id`
- Titles: `titleRU`, `titleEN`, `titleZH`, `titleKO`, `titleJA`
- Descriptions: `descriptionRU`, `descriptionEN`, `descriptionZH`, `descriptionKO`, `descriptionJA`
- Body: `blocksRU`, `blocksEN` (string[])
- Tags: `tagsRU`, `tagsEN`, `tagsZH`, `tagsKO`, `tagsJA` (string[])
- Genres: `genresRU`, `genresEN`, `genresZH`, `genresKO`, `genresJA` (string[])
- Games: `games` (int32[] of game ids), `gamesTitleRU`, `gamesTitleEN` (string[])
- Main tag: `tagMain` (int32[]), `tagMainTitleRU`, `tagMainTitleEN` (string[])
- Metadata: `newsGroupType` (string), `gidOrId` (string)
- Numeric/date: `start`, `finish` (unix seconds), `duration` (seconds)
- Sort token: `_text_match`

Notes:
- Filter by game with numeric id: `filter_by="games:=[12345]"`.
- No queryable numeric tag/genre id — filter by **name** (`tagsEN`/`tagsRU`, `genresEN`/`genresRU`).
- `gidOrId` — group key collapsing all versions of the same story.

#### `games`
- `id`, `title`, `_text_match`
- Search: `"query_by":"title"`. Returns `{id, title}` per hit.

#### `tags` and `genres`
- `id`, `titleRU`, `titleEN`, `titleZH`, `titleKO`, `titleJA`
- `descriptionRU`, `descriptionEN`, `descriptionZH`, `descriptionKO`, `descriptionJA`
- `_text_match`
- Search: `"query_by":"titleEN,titleRU"`.

### Response shape

Ungrouped:
```json
{
  "found": 42,
  "out_of": 10000,
  "page": 1,
  "hits": [
    { "document": { "id": "123", "titleEN": "...", "blocksEN": ["..."], "start": 1717000000 },
      "text_match": 578730 }
  ],
  "filter_by": "games:=[12345]"
}
```

Grouped (when `group_by` is set):
```json
{
  "found": 42,
  "grouped_hits": [
    { "group_key": ["gid987"],
      "hits": [ { "document": { "id": "123", "titleEN": "...", "start": 1717000000 } } ] }
  ]
}
```

### Response validation fields

| Field | Meaning |
|-------|---------|
| `filter_by` | The effective filter sent to the search engine — may differ from what you passed (server appends section scope). Verify your filter was applied correctly. |
| `unknown_params` | Parameters you sent that were silently dropped. If non-empty, check for typos. |

### Article links

```
https://app.sensortower.com/feature-insights/#news/view/{id}
```

### Field meaning cheat-sheet (articles)

- `start` — publish timestamp, unix seconds. Sort by `start:desc` for newest.
- `finish` — end timestamp (events), unix seconds.
- `duration` — seconds.
- `blocksRU` / `blocksEN` — article body split into text blocks; main content for answers.
- `tagsRU/EN/...`, `genresRU/EN/...`, `gamesTitleRU/EN` — human-readable labels.
- `newsGroupType` — article group type; present on grouped articles, absent on standalone.

### HTTP statuses

- `200` — OK.
- `401` — invalid/expired token.
- `402` — (articles only) token quota exhausted.
- `403` — access denied.
- `422` — invalid search request (bad/missing `query_by`, disallowed field, malformed `filter_by`).

---

## Filter & Sort Syntax

Based on Typesense v29. Only parameters accepted by this proxy are covered.

### `q` + `query_by`

- `q` is the search text. `q":"*"` matches everything.
- `query_by` is a comma-separated list of fields. **Required** when `q` is not `"*"`.
- `query_by_weights` assigns relative weights: `"query_by":"titleEN,blocksEN","query_by_weights":"4,1"`.

### `filter_by` — structured filtering

Combine with `&&` (AND) and `||` (OR); group with parentheses.

**Exact match:**
- String/number equals: `field:=value` → `tagsEN:=Update`
- Array membership: `field:=value` → `games:=12345`
- Multiple values (OR): `field:=[a,b,c]` → `games:=[12345,67890]`

**Negation:**
- `field:!=value` → `tagsEN:!=Update`
- `field:!=[a,b]`

**Numeric / date (`start`, `finish`, `duration` — unix seconds):**
- `field:> N`, `field:>= N`, `field:< N`, `field:<= N`
- Range: `field:[MIN..MAX]` → `start:[1704067200..1735689600]`

**Strings with spaces — wrap in backticks:**
```
filter_by: tagsEN:=`Soft Launch`
filter_by: gamesTitleEN:=`Clash of Clans`
```

**Combining:**
```
filter_by: games:=[12345] && start:>=1717200000
filter_by: (tagsEN:=Update || tagsEN:=Event) && start:>=1717200000
filter_by: genresEN:=Strategy && duration:[60..600]
```

### `sort_by`

Comma-separated, up to 3 keys, each `field:asc` or `field:desc`.
- Recency: `sort_by":"start:desc"`
- Relevance: `sort_by":"_text_match:desc"`
- Mixed: `sort_by":"_text_match:desc,start:desc"`

### `group_by` + `group_limit`

Latest version of each story:
```json
{
  "q":"*",
  "filter_by":"games:=[12345]",
  "group_by":"gidOrId",
  "group_limit":1,
  "sort_by":"start:desc"
}
```

### Paging & limits

- `per_page`: 1..250 (default 20).
- `page`: 1..10000.
- `include_fields`: restrict returned fields (comma-separated). `id` always included.
  ```json
  {"q":"*","filter_by":"games:=[12345]","include_fields":"id,titleEN,titleRU,blocksEN,blocksRU,start"}
  ```
