# Playliner AI Plugins

Search Playliner game-industry news, games, tags, and genres directly from your AI coding agent — Claude Code, OpenAI Codex, or Cursor. All answers are grounded strictly in Playliner articles — no hallucination.

Plugin availability is tool-specific:

* **Claude Code** reads the marketplace from `.claude-plugin/marketplace.json`
* **VS Code** uses the same Claude-compatible marketplace format
* **OpenAI Codex** reads the marketplace from `.agents/plugins/marketplace.json`
* **Cursor** reads `.cursor-plugin/marketplace.json` (Team/Enterprise marketplace import)

## Quick start — Claude Code (recommended)

The easiest way — let Claude Code install and drive everything for you:

1. Create a new empty folder and download [`CLAUDE.md`](./user-local-instructions/CLAUDE.md) into it.
2. Start Claude Code in that folder:

   ```
   claude --permission-mode auto
   ```

3. Just send your question about mobile games — e.g. *"latest monetization updates for Clash of Clans"*.

## Quick start — OpenAI Codex

1. Create a new empty folder and download [`AGENTS.md`](./user-local-instructions/AGENTS.md) into it.
2. Start Codex in that folder:

   ```
   codex
   ```

   Approve network and file-write requests when asked (the skill calls
   `app.sensortower.com` with `curl` and stores your API token in `~/.config/playliner/`),
   or run with a permissive approval mode.
3. Send your question about mobile games. On first run the agent offers to install the skill.

## Quick start — Cursor

1. Create a new empty folder and download [`AGENTS.md`](./user-local-instructions/AGENTS.md) into it.
2. Open the folder in Cursor (or run `cursor-agent` in it).
3. Send your question about mobile games. On first run the agent offers to install the skill.

## Manual installation

### Claude Code

Run Claude Code (`claude --permission-mode auto`), then:

```
/plugin marketplace add sensortower/playliner-ai-plugins
/plugin install playliner@playliner-ai-plugins
/reload-plugins
```

Use it:

```
/playliner:playliner-search what are the latest monetization updates for Clash of Clans?
```

### VS Code

Agent plugins consume the same Claude-format marketplace. In `Preferences: Open User Settings (JSON)` add:

```json
{
  "chat.plugins.marketplaces": [
    "sensortower/playliner-ai-plugins"
  ]
}
```

then install `playliner` from the Extensions view (search `@agentPlugins`).

### OpenAI Codex

```bash
codex plugin marketplace add sensortower/playliner-ai-plugins
```

Then, inside a Codex session, run `/plugins`, install `playliner` from the
`playliner-ai-plugins` marketplace, and start a new session.
Invoke with `$playliner-search <your question>` (or via `/skills`).
Update later with `codex plugin marketplace upgrade playliner-ai-plugins`.

Zero-install alternative: copy `plugins/playliner/skills/playliner-search/` from this repo into `~/.agents/skills/`.

### Cursor

Individual users: clone this repo and copy the skill into Cursor's skills folder:

```bash
git clone --depth 1 https://github.com/sensortower/playliner-ai-plugins
mkdir -p ~/.cursor/skills
cp -r playliner-ai-plugins/plugins/playliner/skills/playliner-search ~/.cursor/skills/
```

Invoke with `/playliner-search` in the Agent chat, or just ask the agent to "use the playliner-search skill".

Team/Enterprise: an admin can import this repo as a team marketplace (Dashboard → Plugins → Team Marketplaces → Add Marketplace → Import from Repo), after which the plugin installs from the marketplace panel.

On first use, the skill will ask for your Playliner API token. You can find it on the [API settings page](https://app.sensortower.com/users/edit/api-settings).

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

- One of: Claude Code (claude.ai/code), OpenAI Codex, Cursor, or VS Code with agent plugins
- `bash` and `curl` for the bundled API helper (on Windows: Git Bash or WSL)

## Contributing

See [`CLAUDE.md`](./CLAUDE.md) for the maintainer release checklist.
