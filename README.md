# Playliner Claude Code Plugin

Search Playliner game-industry news, games, tags, and genres directly from Claude Code. All answers are grounded strictly in Playliner articles — no hallucination.

## Quick start (recommended)

The easiest way — let Claude Code install and drive everything for you:

1. Create a new empty folder and download [`CLAUDE.md`](./user-local-instructions/CLAUDE.md) into it.
2. Start Claude Code in that folder:

   ```
   claude --permission-mode auto
   ```

3. Just send your question about mobile games — e.g. *"latest monetization updates for Clash of Clans"*.

## Manual installation

If you'd rather install the plugin yourself:

### 1. Add the Playliner marketplace

Run Claude Code:

```
claude --permission-mode auto
```

In Claude Code, run:

```
/plugin marketplace add sensortower/playliner-ai-plugins
```

### 2. Install the plugin

```
/plugin install playliner@playliner-ai-plugins
```

### 3. Reload plugins

```
/reload-plugins
```

### 4. Use it

```
/playliner:playliner-search what are the latest monetization updates for Clash of Clans?
```

On first use, the plugin will ask for your Playliner Bearer token. You can find it on the [Playliner Premium page](https://app.sensortower.com/feature-insights/#premium).

## Billing for article views

Data credits are charged for viewing each article, but only the first time it is viewed. Subsequent views of the same article are free.

### Formula

```
COST(article) = TEXT + IMAGES + VIDEO

TEXT   = ceil(chars / 4)

IMAGES = count_images × 47

VIDEO  = Σ VIDEO_DATA_CREDIT_COSTᵢ
```

`VIDEO_DATA_CREDIT_COST` is the data credit cost of a single video and depends on its duration:

| Duration range      | Data credits |
|---------------------|--------|
| d < 5 s             | 94     |
| 5 s ≤ d < 30 s      | 141    |
| 30 s ≤ d < 60 s     | 188    |
| 60 s ≤ d < 120 s    | 235    |
| 120 s ≤ d < 240 s   | 282    |
| 240 s ≤ d < 420 s   | 329    |
| d ≥ 420 s           | 376    |

### Example

An article with 2400 characters of text, 5 images, and 2 videos (15 s and 1.5 min):

```
TEXT   = ceil(2400 / 4)        = 600
IMAGES = 5 × 47                = 235
VIDEO  = 141 (15 s) + 235 (90 s) = 376

COST   = 600 + 235 + 376      = 1211 data credits
```

## Requirements

- Claude Code (claude.ai/code)
