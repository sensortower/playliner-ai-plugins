#!/usr/bin/env bash
set -euo pipefail

ERRORS=0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$ROOT/plugins"

error() {
  echo "ERROR: $1" >&2
  ERRORS=$((ERRORS + 1))
}

is_valid_kebab_name() {
  echo "$1" | grep -qE '^[a-z][a-z0-9-]*$'
}

has_frontmatter() {
  head -1 "$1" | grep -q '^---$'
}

extract_frontmatter_name() {
  awk 'BEGIN{f=0} /^---/{f++; next} f==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$1"
}

# 1. Plugin folder names must be lowercase with hyphens only
validate_plugin_folders() {
  echo "Checking plugin folder names..."
  for dir in "$PLUGINS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    name=$(basename "$dir")
    if ! is_valid_kebab_name "$name"; then
      error "Plugin folder '$name': must contain only lowercase letters, numbers, and hyphens"
    fi
  done
}

# 2. plugin.json files must follow the plugin spec
validate_plugin_jsons() {
  echo "Checking plugin.json files..."
  for plugin_json in "$PLUGINS_DIR"/*/.claude-plugin/plugin.json; do
    [[ -f "$plugin_json" ]] || continue
    rel="${plugin_json#"$ROOT/"}"

    if ! jq empty "$plugin_json" 2>/dev/null; then
      error "$rel: invalid JSON"
      continue
    fi

    name=$(jq -r '.name // empty' "$plugin_json")
    if [[ -z "$name" ]]; then
      error "$rel: missing required 'name' field"
    elif ! is_valid_kebab_name "$name"; then
      error "$rel: 'name' must be lowercase letters, numbers, and hyphens only (got: '$name')"
    fi

    version=$(jq -r '.version // empty' "$plugin_json")
    if [[ -n "$version" ]] && ! echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
      error "$rel: 'version' must follow semantic versioning (got: '$version')"
    fi

    for field in commands agents skills outputStyles; do
      paths=$(jq -r "
        if .$field == null then empty
        elif (.$field | type) == \"array\" then .${field}[]
        else .$field
        end
      " "$plugin_json" 2>/dev/null) || true
      while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        if [[ "$path" != ./* ]]; then
          error "$rel: '$field' path '$path' must start with './'"
        fi
      done <<< "$paths"
    done
  done
}

# 3. marketplace.json must reflect the current plugin state
validate_marketplace() {
  echo "Checking marketplace.json..."
  bash "$ROOT/update-marketplace.sh" > /dev/null

  if ! git -C "$ROOT" diff --exit-code .claude-plugin/marketplace.json > /dev/null 2>&1; then
    error "marketplace.json is out of date — run update-marketplace.sh to regenerate"
    git -C "$ROOT" checkout -- .claude-plugin/marketplace.json 2>/dev/null || true
  fi
}

# 4. Skills, commands, and agents must have a valid lowercase-hyphen name: header
validate_components() {
  echo "Checking skills, commands, and agents..."
  for skill_file in "$PLUGINS_DIR"/*/skills/*/SKILL.md; do
    [[ -f "$skill_file" ]] || continue
    rel="${skill_file#"$ROOT/"}"

    if ! has_frontmatter "$skill_file"; then
      error "$rel: missing frontmatter (file must begin with ---)"
      continue
    fi

    name=$(extract_frontmatter_name "$skill_file")
    if [[ -z "$name" ]]; then
      error "$rel: missing required 'name:' in frontmatter"
    elif ! is_valid_kebab_name "$name"; then
      error "$rel: 'name: $name' must be lowercase letters, numbers, and hyphens only"
    fi
  done

  for agent_file in "$PLUGINS_DIR"/*/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    rel="${agent_file#"$ROOT/"}"

    if ! has_frontmatter "$agent_file"; then
      error "$rel: missing frontmatter (file must begin with ---)"
      continue
    fi

    name=$(extract_frontmatter_name "$agent_file")
    if [[ -z "$name" ]]; then
      error "$rel: missing required 'name:' in frontmatter"
    elif ! is_valid_kebab_name "$name"; then
      error "$rel: 'name: $name' must be lowercase letters, numbers, and hyphens only"
    fi
  done
}

validate_plugin_folders
validate_plugin_jsons
validate_marketplace
validate_components

echo ""
if [[ $ERRORS -gt 0 ]]; then
  echo "Validation failed with $ERRORS error(s)." >&2
  exit 1
fi
echo "All validations passed."
