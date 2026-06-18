# Playliner Claude Code Plugin

Search Playliner game-industry news, games, tags, and genres directly from Claude Code. All answers are grounded strictly in Playliner articles — no hallucination.

## Installation

### 1. Add the Playliner marketplace

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

On first use, the plugin will ask for your Playliner Bearer token. The token is stored
locally at `~/.config/playliner/credentials` with `0600` permissions and is never
shared outside your machine.

## Requirements

- Claude Code (claude.ai/code)
- A valid Playliner API Bearer token (contact your Sensortower account manager)
- `curl` available in your shell

## What it does

- Resolves natural-language queries (game names, tags, genres) into Typesense search filters
- Searches Playliner articles via `/api/external/articles`
- Caches game/tag/genre lookups locally for 7 days to minimize API calls
- Cites every fact with article title, link, and date
- Refuses to answer from outside the returned articles
