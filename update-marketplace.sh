#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$ROOT/plugins"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"

plugins_json="[]"

for plugin_json in "$PLUGINS_DIR"/*/.claude-plugin/plugin.json; do
  [[ -f "$plugin_json" ]] || continue

  plugin_dir=$(dirname "$(dirname "$plugin_json")")
  plugin_name=$(basename "$plugin_dir")
  name=$(jq -r '.name // empty' "$plugin_json")
  description=$(jq -r '.description // empty' "$plugin_json")
  source="./plugins/$plugin_name"

  entry=$(jq -n \
    --arg name "$name" \
    --arg description "$description" \
    --arg source "$source" \
    '{"name": $name, "description": $description, "source": $source}')

  plugins_json=$(echo "$plugins_json" | jq ". + [$entry]")
done

tmp=$(mktemp)
jq --argjson plugins "$plugins_json" '.plugins = $plugins' "$MARKETPLACE" > "$tmp"
mv "$tmp" "$MARKETPLACE"

echo "Updated $MARKETPLACE with $(echo "$plugins_json" | jq 'length') plugin(s)."
