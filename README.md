# Playliner AI Plugins

Search Playliner game-industry news, games, tags, and genres directly from your AI coding agent — Claude Code, OpenAI Codex, or Cursor. All answers are grounded strictly in Playliner articles — no hallucination.

Plugin availability is tool-specific:

* **Claude Code** reads the marketplace from `.claude-plugin/marketplace.json`
* **OpenAI Codex** reads the marketplace from `.agents/plugins/marketplace.json`
* **Cursor** reads `.cursor-plugin/marketplace.json` (Team/Enterprise marketplace import)

## Quick start — Claude Code (recommended)

The easiest way — let Claude Code install and drive everything for you:

1. Create a new empty folder and download [`CLAUDE.md`](./user-local-instructions/claude/CLAUDE.md) into it.
2. Start Claude Code in that folder:

   ```
   claude --permission-mode auto
   ```

3. Just send your question about mobile games — e.g. *"latest monetization updates for Clash of Clans"*.

## Quick start — OpenAI Codex

Requires Codex CLI 0.14x+

1. Create a new empty folder and download [`AGENTS.md`](./user-local-instructions/codex/AGENTS.md) into it.
2. Start Codex in that folder:

   ```
   codex -c sandbox_workspace_write.network_access=true
   ```

3. Just send your question about mobile games — e.g. *"latest monetization updates for Clash of Clans"*.

## Quick start — Cursor

1. Create a new empty folder and download [`AGENTS.md`](./user-local-instructions/cursor/AGENTS.md) into it.
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

### OpenAI Codex

```bash
codex plugin marketplace add sensortower/playliner-ai-plugins
codex plugin add playliner@playliner-ai-plugins
```

Start a new Codex session so the skill loads and verify with the `/plugin` command
(playliner should be listed as installed). Invoke with `$playliner-search <your question>`.

Update later by refreshing the snapshot and re-installing:

```bash
codex plugin marketplace upgrade playliner-ai-plugins
codex plugin add playliner@playliner-ai-plugins
```

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

## Requirements

- One of: Claude Code (claude.ai/code), OpenAI Codex, Cursor, or VS Code with agent plugins
- `bash` and `curl` for the bundled API helper (on Windows: Git Bash or WSL)

## Contributing

See [`CLAUDE.md`](./CLAUDE.md) for the maintainer release checklist.
