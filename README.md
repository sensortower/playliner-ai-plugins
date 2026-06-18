# Playliner Claude Code Plugin

Search Playliner game-industry news, games, tags, and genres directly from Claude Code. All answers are grounded strictly in Playliner articles — no hallucination.

## Installation

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

## Requirements

- Claude Code (claude.ai/code)
