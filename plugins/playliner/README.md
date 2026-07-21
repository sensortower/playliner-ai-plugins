# Playliner

Search Playliner game-industry news, games, tags, and genres directly from your AI coding agent. All answers are grounded strictly in Playliner articles — no hallucination.

[Playliner](https://app.sensortower.com/playliner/) is Sensor Tower's live-ops intelligence product for mobile games: articles about game updates, events, monetization changes, and their measured impact on revenue, downloads, and DAU.

## What the plugin does

The bundled `playliner-search` skill teaches the agent to:

- search Playliner articles, games, tags, and genres through the official API;
- run event-impact analytics queries (revenue, downloads, DAU uptrends);
- answer strictly from the returned articles, with citations.

## Requirements

- `bash` and `curl` (on Windows: Git Bash or WSL)
- A Playliner API token — get it on the [API settings page](https://app.sensortower.com/users/edit/api-settings). The skill asks for it on first use and stores it locally in `~/.config/playliner/credentials`.

## Usage

Invoke the skill with `/playliner-search <your question>`, or just ask about mobile games — e.g. *"latest monetization updates for Clash of Clans"*.
