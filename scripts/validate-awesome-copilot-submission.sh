#!/usr/bin/env bash
# validate-awesome-copilot-submission.sh
#
# Mirrors every blocking CI gate in github/awesome-copilot for a single
# artifact (instructions / agent / skill / hook / workflow / plugin).
#
# Run from inside a clone of github/awesome-copilot:
#   ./validate-awesome-copilot-submission.sh --path instructions/foo.instructions.md
#
# Exit codes:
#   0  all checks passed (warnings OK)
#   1  one or more blocking checks failed
#
# Reference: strategy/awesome-copilot-pipeline-spec.md Section 3 (CI inventory).

set -euo pipefail

ERRORS=0
WARNINGS=0
PATH_ARG=""
TYPE_ARG=""
SKIP_REGEN=0

red()    { printf "\033[31m%s\033[0m\n" "$1"; }
green()  { printf "\033[32m%s\033[0m\n" "$1"; }
yellow() { printf "\033[33m%s\033[0m\n" "$1"; }
blue()   { printf "\033[34m%s\033[0m\n" "$1"; }

error() { red "ERROR: $1"; ERRORS=$((ERRORS + 1)); }
warn()  { yellow "WARN:  $1"; WARNINGS=$((WARNINGS + 1)); }
pass()  { green "PASS:  $1"; }
info()  { blue  "INFO:  $1"; }

usage() {
    cat <<'EOF'
Usage: validate-awesome-copilot-submission.sh [options]

Options:
  --path <path>          Artifact path relative to repo root (e.g. instructions/foo.instructions.md)
  --type <type>          Force artifact type: instructions|agent|skill|hook|workflow|plugin
  --skip-regen           Skip the npm start README regeneration step (faster local iteration)
  -h, --help             Show this help

If --path is omitted, the script inspects `git diff --name-only origin/staged...HEAD`
and validates every changed artifact in turn.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --path) PATH_ARG="$2"; shift 2 ;;
        --type) TYPE_ARG="$2"; shift 2 ;;
        --skip-regen) SKIP_REGEN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

echo "=== Step 1: Preflight ==="

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
    error "Not inside a git repository. Run from a clone of github/awesome-copilot."
    exit 1
fi
cd "$REPO_ROOT"

ORIGIN_URL=$(git config --get remote.origin.url || true)
case "$ORIGIN_URL" in
    *github/awesome-copilot*|*RoninForge/awesome-copilot*)
        pass "git repo is awesome-copilot (origin: $ORIGIN_URL)" ;;
    *)
        warn "origin does not look like awesome-copilot (got: $ORIGIN_URL)"
        ;;
esac

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
case "$CURRENT_BRANCH" in
    main|staged)
        warn "On branch '$CURRENT_BRANCH'. Authoring branches MUST be cut from origin/staged (NEVER main)." ;;
    *) pass "On feature branch '$CURRENT_BRANCH'" ;;
esac

# Required tools
for tool in node npm jq git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        error "Required tool missing: $tool"
    fi
done
if command -v codespell >/dev/null 2>&1; then
    pass "codespell available"
else
    warn "codespell not installed; spelling check will be skipped (CI will run it)"
fi

NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo "0")
if [ "$NODE_MAJOR" -lt 20 ]; then
    error "Node.js must be >= 20 (got $NODE_MAJOR.x). awesome-copilot CI uses node 20+."
else
    pass "Node $(node -v)"
fi

echo ""
echo "=== Step 2: Install deps ==="

if [ ! -d node_modules ]; then
    info "Running npm ci (first time)"
    npm ci --silent 2>&1 | tail -3
else
    pass "node_modules present"
fi

# ---------------------------------------------------------------------------
# Detect artifact paths to validate
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 3: Detect artifact(s) ==="

PATHS=""
if [ -n "$PATH_ARG" ]; then
    PATHS="$PATH_ARG"
else
    if git rev-parse --verify origin/staged >/dev/null 2>&1; then
        PATHS=$(git diff --name-only origin/staged...HEAD -- \
            'instructions/**' 'agents/**' 'skills/**' 'hooks/**' 'workflows/**' 'plugins/**' \
            2>/dev/null | grep -vE '/\.gitkeep$' || true)
    fi
fi

if [ -z "$PATHS" ]; then
    warn "No artifact paths detected. Use --path to specify."
    exit 0
fi

info "Validating paths:"
echo "$PATHS" | sed 's/^/   /'

detect_type() {
    case "$1" in
        instructions/*.instructions.md) echo instructions ;;
        agents/*.agent.md)              echo agent ;;
        skills/*/SKILL.md|skills/*)     echo skill ;;
        hooks/*/README.md|hooks/*)      echo hook ;;
        workflows/*.md)                 echo workflow ;;
        plugins/*/.github/plugin/plugin.json|plugins/*) echo plugin ;;
        *) echo "" ;;
    esac
}

echo ""
echo "=== Step 4-9: Per-artifact checks ==="

while IFS= read -r p; do
    [ -z "$p" ] && continue
    [ -e "$p" ] || { error "$p does not exist"; continue; }

    if [ -n "$TYPE_ARG" ]; then
        ARTIFACT_TYPE="$TYPE_ARG"
    else
        ARTIFACT_TYPE=$(detect_type "$p")
    fi
    if [ -z "$ARTIFACT_TYPE" ]; then
        error "Cannot detect artifact type for $p (use --type to force)"
        continue
    fi

    echo ""
    info "Checking $p (type: $ARTIFACT_TYPE)"

    BASENAME=$(basename "$p")
    case "$ARTIFACT_TYPE" in
        instructions)
            echo "$BASENAME" | grep -qE '^[a-z0-9-]+\.instructions\.md$' \
                && pass "naming: lowercase-kebab .instructions.md" \
                || error "naming: must match /^[a-z0-9-]+\.instructions\.md$/ (got $BASENAME)"
            ;;
        agent)
            echo "$BASENAME" | grep -qE '^[a-z0-9-]+\.agent\.md$' \
                && pass "naming: lowercase-kebab .agent.md" \
                || warn "naming: prefer lowercase-kebab .agent.md (got $BASENAME; legacy CamelCase exists but not for new entries)"
            ;;
        skill|hook|plugin)
            FOLDER=$(basename "$(dirname "$p")")
            echo "$FOLDER" | grep -qE '^[a-z0-9-]+$' \
                && pass "naming: folder $FOLDER is lowercase-kebab" \
                || error "naming: folder $FOLDER must match /^[a-z0-9-]+$/"
            ;;
        workflow)
            echo "$BASENAME" | grep -qE '^[a-z0-9-]+\.md$' \
                && pass "naming: lowercase-kebab .md" \
                || error "naming: workflow file must match /^[a-z0-9-]+\.md$/"
            for sibling in "${p%.md}.yml" "${p%.md}.yaml" "${p%.md}.lock.yml"; do
                if [ -e "$sibling" ]; then
                    error "workflow has forbidden compiled sibling: $sibling (CI blocks)"
                fi
            done
            ;;
    esac

    case "$ARTIFACT_TYPE" in
        instructions|agent|workflow|hook)
            FRONTMATTER_FILE="$p"
            case "$ARTIFACT_TYPE" in
                hook) FRONTMATTER_FILE="$p" ;;
            esac
            if [ "${FRONTMATTER_FILE##*.}" = "md" ]; then
                FIRST_LINE=$(head -1 "$FRONTMATTER_FILE" || true)
                if [ "$FIRST_LINE" = "---" ]; then
                    pass "frontmatter: opens with ---"
                    case "$ARTIFACT_TYPE" in
                        instructions)
                            grep -qE '^description:' "$FRONTMATTER_FILE" \
                                && pass "frontmatter: description present" \
                                || error "frontmatter: description required"
                            grep -qE "^applyTo:[[:space:]]*['\"]" "$FRONTMATTER_FILE" \
                                && pass "frontmatter: applyTo present (quoted)" \
                                || error "frontmatter: applyTo required (single-quoted glob)"
                            ;;
                        agent)
                            grep -qE '^name:' "$FRONTMATTER_FILE" \
                                && pass "frontmatter: name present" \
                                || error "frontmatter: name required"
                            grep -qE '^description:' "$FRONTMATTER_FILE" \
                                && pass "frontmatter: description present" \
                                || error "frontmatter: description required"
                            grep -qE '^model:' "$FRONTMATTER_FILE" \
                                || warn "frontmatter: model recommended"
                            ;;
                        workflow)
                            for f in name description on permissions; do
                                grep -qE "^${f}:" "$FRONTMATTER_FILE" \
                                    && pass "frontmatter: $f present" \
                                    || error "frontmatter: $f required for workflows"
                            done
                            ;;
                        hook)
                            grep -qE '^name:' "$FRONTMATTER_FILE" \
                                && pass "frontmatter: name present" \
                                || error "frontmatter: name required"
                            grep -qE '^description:' "$FRONTMATTER_FILE" \
                                && pass "frontmatter: description required"
                            ;;
                    esac
                else
                    error "frontmatter: $FRONTMATTER_FILE missing YAML frontmatter (must start with ---)"
                fi
            fi
            ;;
        skill)
            SKILL_DIR="$p"
            [ -f "$p" ] && SKILL_DIR="$(dirname "$p")"
            SKILL_MD="$SKILL_DIR/SKILL.md"
            if [ ! -f "$SKILL_MD" ]; then
                error "skill: $SKILL_DIR missing SKILL.md"
            else
                pass "skill: SKILL.md present"
                if [ "$(head -1 "$SKILL_MD")" = "---" ]; then
                    SKILL_NAME=$(grep '^name:' "$SKILL_MD" | head -1 | sed 's/name: *//' | tr -d '"' | tr -d "'")
                    SKILL_FOLDER=$(basename "$SKILL_DIR")
                    if [ "$SKILL_NAME" = "$SKILL_FOLDER" ]; then
                        pass "skill: name matches folder"
                    else
                        error "skill: name '$SKILL_NAME' must equal folder '$SKILL_FOLDER'"
                    fi
                    echo "$SKILL_NAME" | grep -qE '^[a-z0-9-]+$' \
                        && pass "skill: name matches /^[a-z0-9-]+$/" \
                        || error "skill: name '$SKILL_NAME' violates /^[a-z0-9-]+$/"
                else
                    error "skill: SKILL.md missing YAML frontmatter"
                fi
                find "$SKILL_DIR" -type f -size +5M 2>/dev/null | while read -r big; do
                    error "skill: $big exceeds 5MB asset limit"
                done
            fi
            ;;
        plugin)
            PLUGIN_DIR="$p"
            [ -f "$p" ] && PLUGIN_DIR="$(dirname "$(dirname "$(dirname "$p")")")"
            PLUGIN_FOLDER=$(basename "$PLUGIN_DIR")
            if [ ! -f "$PLUGIN_DIR/.github/plugin/plugin.json" ]; then
                error "plugin: $PLUGIN_DIR/.github/plugin/plugin.json missing"
            elif ! jq empty "$PLUGIN_DIR/.github/plugin/plugin.json" >/dev/null 2>&1; then
                error "plugin: plugin.json is not valid JSON"
            else
                pass "plugin: plugin.json valid JSON"
                PJ_NAME=$(jq -r '.name' "$PLUGIN_DIR/.github/plugin/plugin.json")
                if [ "$PJ_NAME" = "$PLUGIN_FOLDER" ]; then
                    pass "plugin: name matches folder"
                else
                    error "plugin: plugin.json name '$PJ_NAME' must equal folder '$PLUGIN_FOLDER'"
                fi
            fi
            for sub in agents commands skills; do
                if [ -d "$PLUGIN_DIR/$sub" ] && [ -n "$(ls -A "$PLUGIN_DIR/$sub" 2>/dev/null)" ]; then
                    error "plugin (staged-shape): $PLUGIN_DIR/$sub must be empty/absent on staged; CI publish-job materializes on merge to main"
                fi
            done
            find "$PLUGIN_DIR" -type l 2>/dev/null | while read -r link; do
                error "plugin: symlink found at $link (check-plugin-structure.yml blocks)"
            done
            ;;
    esac

    if [ "$ARTIFACT_TYPE" = "instructions" ]; then
        BODY_LINE=$(awk '/^---$/{c++; next} c==2 && /[^[:space:]]/ {print NR": "$0; exit}' "$p" || true)
        if echo "$BODY_LINE" | grep -qE '^[0-9]+:[[:space:]]*#[[:space:]]'; then
            pass "content: body starts with '# '"
        else
            warn "content: body should start with a top-level '# Heading' (got: $BODY_LINE)"
        fi
    fi
done <<< "$PATHS"

echo ""
echo "=== Step 10: Line-ending check (CRLF blocks CI) ==="

CRLF_HITS=$(find . \( -name node_modules -prune -o -name '.git' -prune \) -o -type f -name '*.md' -print0 \
    | xargs -0 grep -l $'\r' 2>/dev/null || true)
if [ -z "$CRLF_HITS" ]; then
    pass "no CRLF line endings in *.md"
else
    error "CRLF found in:"
    echo "$CRLF_HITS"
    info "Fix with: bash eng/fix-line-endings.sh"
fi

echo ""
echo "=== Step 11: codespell ==="

if command -v codespell >/dev/null 2>&1; then
    CODESPELL_TARGETS="$PATHS"
    if codespell --check-filenames --config .codespellrc $CODESPELL_TARGETS 2>&1 | grep -E ' ==> '; then
        error "codespell found typos (above)"
    else
        pass "codespell clean"
    fi
else
    warn "codespell skipped (not installed)"
fi

echo ""
echo "=== Step 12: Workflow compile check (gh-aw) ==="

WORKFLOW_PATHS=$(echo "$PATHS" | grep '^workflows/' || true)
if [ -n "$WORKFLOW_PATHS" ]; then
    if gh extension list 2>/dev/null | grep -q github/gh-aw; then
        pass "gh-aw extension installed"
    else
        info "Installing gh-aw extension"
        gh extension install github/gh-aw 2>&1 | tail -2 || warn "gh extension install failed"
    fi
    while IFS= read -r wf; do
        [ -z "$wf" ] && continue
        if gh aw compile --validate "$wf" 2>&1 | tail -5; then
            pass "gh aw compile --validate $wf"
        else
            error "gh aw compile failed for $wf"
        fi
    done <<< "$WORKFLOW_PATHS"
else
    info "no workflows changed; skipping gh-aw"
fi

echo ""
echo "=== Step 13: Plugin validator (npm run plugin:validate) ==="

PLUGIN_PATHS=$(echo "$PATHS" | grep '^plugins/' || true)
if [ -n "$PLUGIN_PATHS" ]; then
    if npm run plugin:validate --silent 2>&1 | tail -10; then
        pass "plugin:validate exit 0"
    else
        error "plugin:validate failed"
    fi
else
    info "no plugins changed; skipping plugin:validate"
fi

echo ""
echo "=== Step 14: Skill validator (npm run skill:validate; warn-only) ==="

SKILL_PATHS=$(echo "$PATHS" | grep -E '^skills/|^agents/' || true)
if [ -n "$SKILL_PATHS" ]; then
    if npm run skill:validate --silent 2>&1 | tail -10; then
        pass "skill:validate exit 0"
    else
        warn "skill:validate reported issues (CI is warn-only but maintainers may gate)"
    fi
else
    info "no skills/agents changed; skipping skill:validate"
fi

echo ""
echo "=== Step 15: README regeneration (validate-readme.yml is the #1 bounce) ==="

if [ "$SKIP_REGEN" -eq 1 ]; then
    warn "Skipped npm start (--skip-regen). CI runs it; you MUST run before pushing."
else
    info "Running npm start..."
    if npm start --silent 2>&1 | tail -5; then
        pass "npm start completed"
    else
        error "npm start failed"
    fi
    DIRTY=$(git diff --name-only)
    if [ -z "$DIRTY" ]; then
        pass "no README/marketplace drift after npm start"
    else
        error "README/marketplace drift after npm start. Files changed:"
        echo "$DIRTY" | sed 's/^/   /'
        info "Stage those changes and amend the commit, or CI will reject."
    fi
fi

echo ""
echo "=== Summary ==="
echo "Errors:   $ERRORS"
echo "Warnings: $WARNINGS"
echo ""
if [ "$ERRORS" -gt 0 ]; then
    red "FAILED - fix $ERRORS error(s) before pushing"
    exit 1
fi
if [ "$WARNINGS" -gt 0 ]; then
    yellow "PASSED with $WARNINGS warning(s)"
else
    green "ALL CHECKS PASSED - ready to push and open PR (base: staged)"
fi
exit 0
