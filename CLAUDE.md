# Maintainer notes

This repo is a multi-platform AI-agent plugin marketplace. Each plugin under
`plugins/<name>/` ships three side-by-side manifests — `.claude-plugin/plugin.json`
(Claude Code + VS Code), `.cursor-plugin/plugin.json` (Cursor), and
`.codex-plugin/plugin.json` (OpenAI Codex) — around one shared `skills/` tree.
`SKILL.md` is an open standard read by all three platforms; keep it platform-neutral
(no bare tool names or PATH assumptions without a fallback).

Helper scripts live inside the skill (`skills/<skill>/scripts/`), never in a plugin
`bin/` directory — `bin/`-on-PATH only works in Claude Code and validate.sh rejects it.

## Release checklist (when changing the plugin)

1. Bump `version` **identically** in all three plugin.json manifests
   (`.claude-plugin/`, `.cursor-plugin/`, `.codex-plugin/`) — `name` and
   `description` must also stay identical; validate.sh enforces this.
2. Run `./update-marketplace.sh` — regenerates all three marketplace catalogs:
   `.claude-plugin/marketplace.json`, `.cursor-plugin/marketplace.json`,
   `.agents/plugins/marketplace.json`.
3. Run `./validate.sh` (CI runs it on every push/PR).
4. **Merging to `master` is releasing**: the Codex marketplace references this repo
   by public git URL with `ref: master`, and Claude marketplace updates pull the
   branch tip too.
