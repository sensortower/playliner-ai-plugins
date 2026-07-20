#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$ROOT/plugins"

# The Codex marketplace references plugins by public git URL, so merging to
# $REPO_REF is effectively a release for Codex users.
REPO_URL="https://github.com/sensortower/playliner-ai-plugins.git"
REPO_REF="master"

# Flat marketplace schema (Claude Code / VS Code and Cursor):
# a plugin is listed only if it has the platform's plugin.json.
update_marketplace() {
  local manifest_dir="$1"
  local marketplace="$2"
  local plugins_json="[]"

  for plugin_json in "$PLUGINS_DIR"/*/"$manifest_dir"/plugin.json; do
    [[ -f "$plugin_json" ]] || continue

    local plugin_dir plugin_name name description entry
    plugin_dir=$(dirname "$(dirname "$plugin_json")")
    plugin_name=$(basename "$plugin_dir")
    name=$(jq -r '.name // empty' "$plugin_json")
    description=$(jq -r '.description // empty' "$plugin_json")

    entry=$(jq -n \
      --arg name "$name" \
      --arg description "$description" \
      --arg source "./plugins/$plugin_name" \
      '{"name": $name, "description": $description, "source": $source}')

    plugins_json=$(echo "$plugins_json" | jq ". + [$entry]")
  done

  local tmp
  tmp=$(mktemp)
  jq --argjson plugins "$plugins_json" '.plugins = $plugins' "$marketplace" > "$tmp"
  mv "$tmp" "$marketplace"

  echo "Updated ${marketplace#"$ROOT/"} with $(echo "$plugins_json" | jq 'length') plugin(s)."
}

# Codex marketplace schema: git-subdir source pointing at the public repo.
# Per the Codex spec each plugin entry must carry `category` and a `policy`
# with `installation` + `authentication` (this skill authenticates on install).
# `category` and `policy` are read from .codex-plugin/plugin.json with defaults.
update_codex_marketplace() {
  local marketplace="$ROOT/.agents/plugins/marketplace.json"
  local plugins_json="[]"

  for plugin_json in "$PLUGINS_DIR"/*/.codex-plugin/plugin.json; do
    [[ -f "$plugin_json" ]] || continue

    local plugin_dir plugin_name name description category installation authentication entry
    plugin_dir=$(dirname "$(dirname "$plugin_json")")
    plugin_name=$(basename "$plugin_dir")
    name=$(jq -r '.name // empty' "$plugin_json")
    description=$(jq -r '.description // empty' "$plugin_json")
    category=$(jq -r '.category // "Productivity"' "$plugin_json")
    installation=$(jq -r '.policy.installation // "AVAILABLE"' "$plugin_json")
    authentication=$(jq -r '.policy.authentication // "ON_INSTALL"' "$plugin_json")

    entry=$(jq -n \
      --arg name "$name" \
      --arg description "$description" \
      --arg category "$category" \
      --arg installation "$installation" \
      --arg authentication "$authentication" \
      --arg url "$REPO_URL" \
      --arg path "./plugins/$plugin_name" \
      --arg ref "$REPO_REF" \
      '{"name": $name, "description": $description, "category": $category,
        "policy": {"installation": $installation, "authentication": $authentication},
        "source": {"source": "git-subdir", "url": $url, "path": $path, "ref": $ref}}')

    plugins_json=$(echo "$plugins_json" | jq ". + [$entry]")
  done

  local tmp
  tmp=$(mktemp)
  jq --argjson plugins "$plugins_json" '.plugins = $plugins' "$marketplace" > "$tmp"
  mv "$tmp" "$marketplace"

  echo "Updated ${marketplace#"$ROOT/"} with $(echo "$plugins_json" | jq 'length') plugin(s)."
}

update_marketplace ".claude-plugin" "$ROOT/.claude-plugin/marketplace.json"
update_marketplace ".cursor-plugin" "$ROOT/.cursor-plugin/marketplace.json"
update_codex_marketplace
