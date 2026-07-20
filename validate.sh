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

# 2. plugin.json files must follow the plugin spec (all platforms)
validate_plugin_jsons() {
  echo "Checking plugin.json files..."
  for plugin_json in \
    "$PLUGINS_DIR"/*/.claude-plugin/plugin.json \
    "$PLUGINS_DIR"/*/.cursor-plugin/plugin.json \
    "$PLUGINS_DIR"/*/.codex-plugin/plugin.json; do
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

# 2b. Every plugin must ship all three platform manifests, and their
#     name/version/description must be identical (single source of truth).
validate_manifest_consistency() {
  echo "Checking cross-platform manifest consistency..."
  for dir in "$PLUGINS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    local_rel="${dir#"$ROOT/"}"

    local ref_json="" ref_manifest=""
    for manifest_dir in .claude-plugin .cursor-plugin .codex-plugin; do
      manifest="$dir$manifest_dir/plugin.json"
      if [[ ! -f "$manifest" ]]; then
        error "${local_rel}: missing $manifest_dir/plugin.json (all plugins must support Claude Code, Cursor, and Codex)"
        continue
      fi
      fields=$(jq -S '{name, version, description}' "$manifest" 2>/dev/null) || continue
      if [[ -z "$ref_json" ]]; then
        ref_json="$fields"
        ref_manifest="$manifest_dir"
      elif [[ "$fields" != "$ref_json" ]]; then
        error "${local_rel}: $manifest_dir/plugin.json name/version/description differ from $ref_manifest/plugin.json — keep them identical"
      fi
    done
  done
}

# 2c. The Claude-only bin/-on-PATH layout must not come back — helper scripts
#     belong inside the skill (skills/<skill>/scripts/) so all platforms find them.
validate_no_bin_dirs() {
  for dir in "$PLUGINS_DIR"/*/bin; do
    [[ -d "$dir" ]] || continue
    error "${dir#"$ROOT/"}: plugin bin/ directories are not allowed — put scripts in skills/<skill>/scripts/ instead"
  done
}

# 3. marketplace files must reflect the current plugin state.
# Compare a fresh regeneration against the on-disk files directly (not via
# `git diff`, which ignores untracked files) so drift is caught even before the
# catalogs are committed.
validate_marketplace() {
  echo "Checking marketplace files..."

  local marketplaces=(
    ".claude-plugin/marketplace.json"
    ".cursor-plugin/marketplace.json"
    ".agents/plugins/marketplace.json"
  )

  # Snapshot the current files, regenerate, compare, then restore.
  # All three files are named marketplace.json, so flatten the path for a
  # unique backup filename (basename alone would collide and clobber).
  local backup
  backup=$(mktemp -d)
  for marketplace in "${marketplaces[@]}"; do
    saved="$backup/${marketplace//\//_}"
    [[ -f "$ROOT/$marketplace" ]] && cp "$ROOT/$marketplace" "$saved"
  done

  bash "$ROOT/update-marketplace.sh" > /dev/null

  for marketplace in "${marketplaces[@]}"; do
    saved="$backup/${marketplace//\//_}"
    if [[ ! -f "$saved" ]]; then
      error "$marketplace is missing — run update-marketplace.sh to generate it"
    elif ! cmp -s "$saved" "$ROOT/$marketplace"; then
      error "$marketplace is out of date — run update-marketplace.sh to regenerate"
    fi
    # Restore the pre-check version so validation never mutates the tree.
    [[ -f "$saved" ]] && cp "$saved" "$ROOT/$marketplace"
  done

  rm -rf "$backup"
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

    if ! awk 'BEGIN{f=0} /^---/{f++; next} f==1 && /^description:[[:space:]]*[^[:space:]]/{found=1; exit} END{exit !found}' "$skill_file"; then
      error "$rel: missing required 'description:' in frontmatter (needed by Claude Code, Cursor, and Codex)"
    fi
  done

  for script_file in "$PLUGINS_DIR"/*/skills/*/scripts/*; do
    [[ -f "$script_file" ]] || continue
    if [[ ! -x "$script_file" ]]; then
      error "${script_file#"$ROOT/"}: must be executable (chmod +x)"
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
validate_manifest_consistency
validate_no_bin_dirs
validate_marketplace
validate_components

echo ""
if [[ $ERRORS -gt 0 ]]; then
  echo "Validation failed with $ERRORS error(s)." >&2
  exit 1
fi
echo "All validations passed."
