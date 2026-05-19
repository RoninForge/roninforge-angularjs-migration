#!/usr/bin/env bash
# submit-to-awesome-copilot.sh
#
# End-to-end: take a source-of-truth package from ~/development/roninforge-<name>/,
# fork (or sync existing fork of) github/awesome-copilot, branch from staged,
# copy dist/ artifacts to the correct upstream paths, run npm start, validate,
# commit, push, open PR.
#
# Reference: strategy/awesome-copilot-pipeline-spec.md Section 6.
#
# Usage:
#   submit-to-awesome-copilot.sh [--source <path>] [--dry-run] [--no-pr]
#
#   --source <path>   Source repo path (default: $PWD; must contain META.yml)
#   --dry-run         Stop before push (still creates branch + commit locally)
#   --no-pr           Push branch but do not open PR
#
# Exit codes:
#   0  PR opened (or branch pushed in --no-pr mode)
#   1  any failure (preflight, validator, regeneration, gh auth)

set -euo pipefail

SOURCE_DIR="${PWD}"
DRY_RUN=0
NO_PR=0

red()   { printf "\033[31m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
blue()  { printf "\033[34m%s\033[0m\n" "$1"; }

step() { echo ""; blue "=== $1 ==="; }
err()  { red "ERROR: $1"; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --source)  SOURCE_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --no-pr)   NO_PR=1; shift ;;
        -h|--help)
            sed -n '2,18p' "$0"
            exit 0 ;;
        *) err "Unknown option: $1" ;;
    esac
done

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
META="$SOURCE_DIR/META.yml"
[ -f "$META" ] || err "META.yml not found in $SOURCE_DIR"

step "1: Read META.yml"

read_meta() {
    awk -v key="$1" '
        $1 == key":"          { sub(/^[^:]*:[[:space:]]*/, "", $0); print; exit }
        $1 == key && $2 == "" {
            # block scalar
            while ((getline line) > 0) {
                if (line ~ /^[a-zA-Z_]/) break
                gsub(/^[[:space:]]+/, "", line)
                printf "%s ", line
            }
            print ""; exit
        }
    ' "$META"
}

SLUG=$(read_meta slug | tr -d '"' | tr -d "'" | xargs)
TYPE=$(read_meta type | tr -d '"' | tr -d "'" | xargs)
VERSION=$(read_meta version | tr -d '"' | tr -d "'" | xargs)

[ -n "$SLUG" ]    || err "META.yml: slug is required"
[ -n "$TYPE" ]    || err "META.yml: type is required"
[ -n "$VERSION" ] || err "META.yml: version is required"

echo "  slug:    $SLUG"
echo "  type:    $TYPE"
echo "  version: $VERSION"

case "$TYPE" in
    instructions|agent|skill|hook|workflow|plugin) ;;
    *) err "META.yml: type must be instructions|agent|skill|hook|workflow|plugin (got: $TYPE)" ;;
esac

step "2: gh auth"
if ! gh auth status >/dev/null 2>&1; then
    err "gh CLI is not authenticated. Run: gh auth login"
fi
green "gh auth OK"

UPSTREAM="${SOURCE_DIR}/.upstream-clone"

step "3: Fork + clone upstream"

if [ ! -d "$UPSTREAM" ]; then
    if gh repo view RoninForge/awesome-copilot >/dev/null 2>&1; then
        green "RoninForge/awesome-copilot fork exists"
    else
        echo "Forking github/awesome-copilot to RoninForge..."
        gh repo fork github/awesome-copilot --org RoninForge --default-branch-only=false
    fi
    echo "Cloning fork to $UPSTREAM..."
    gh repo clone RoninForge/awesome-copilot "$UPSTREAM"
fi

cd "$UPSTREAM"

if ! git remote | grep -q '^upstream$'; then
    git remote add upstream https://github.com/github/awesome-copilot.git
fi

step "4: Sync fork with upstream"
git fetch upstream staged main --quiet
git fetch origin --quiet
git checkout -B staged upstream/staged
git push --force-with-lease origin staged:staged >/dev/null 2>&1 || true
green "fork synced to upstream/staged"

step "5: Create feature branch"
BR="roninforge/${SLUG}-$(date +%Y%m%d)"
if git rev-parse --verify "$BR" >/dev/null 2>&1; then
    echo "Branch $BR already exists locally; deleting and re-cutting"
    git checkout staged
    git branch -D "$BR"
fi
git checkout -b "$BR" upstream/staged
green "on branch $BR (cut from upstream/staged)"

step "6: Copy artifacts from dist/"

case "$TYPE" in
    instructions)
        SRC="$SOURCE_DIR/dist/${SLUG}.instructions.md"
        DST="instructions/${SLUG}.instructions.md"
        [ -f "$SRC" ] || err "missing source artifact: $SRC"
        cp "$SRC" "$DST"
        green "copied $SRC -> $DST"
        ;;
    agent)
        SRC="$SOURCE_DIR/dist/${SLUG}.agent.md"
        DST="agents/${SLUG}.agent.md"
        [ -f "$SRC" ] || err "missing source artifact: $SRC"
        cp "$SRC" "$DST"
        green "copied $SRC -> $DST"
        ;;
    skill)
        SRC="$SOURCE_DIR/dist/skill"
        DST="skills/${SLUG}"
        [ -d "$SRC" ] || err "missing source directory: $SRC"
        mkdir -p "$DST"
        rsync -a --delete "$SRC/" "$DST/"
        green "rsynced $SRC/ -> $DST/"
        ;;
    hook)
        SRC="$SOURCE_DIR/dist/hook"
        DST="hooks/${SLUG}"
        [ -d "$SRC" ] || err "missing source directory: $SRC"
        mkdir -p "$DST"
        rsync -a --delete "$SRC/" "$DST/"
        find "$DST" -name '*.sh' -exec chmod +x {} \;
        green "rsynced + chmod +x $SRC/ -> $DST/"
        ;;
    workflow)
        SRC="$SOURCE_DIR/dist/${SLUG}.md"
        DST="workflows/${SLUG}.md"
        [ -f "$SRC" ] || err "missing source artifact: $SRC"
        cp "$SRC" "$DST"
        green "copied $SRC -> $DST"
        ;;
    plugin)
        SRC="$SOURCE_DIR/dist/plugin"
        DST="plugins/${SLUG}"
        [ -d "$SRC" ] || err "missing source directory: $SRC"
        mkdir -p "$DST"
        rsync -a --delete "$SRC/" "$DST/"
        green "rsynced $SRC/ -> $DST/ (must be staged-shape: only .github/plugin/plugin.json + README.md)"
        ;;
esac

step "7: Run validator (skip-regen; submit script does regen itself in step 8)"
VALIDATOR="$SOURCE_DIR/scripts/validate-awesome-copilot-submission.sh"
[ -x "$VALIDATOR" ] || err "validator missing or not executable: $VALIDATOR"

if ! "$VALIDATOR" --path "$DST" --skip-regen; then
    err "Validator failed on naming/frontmatter/content/CRLF/codespell. Fix in $SOURCE_DIR/dist/ and re-run."
fi

step "8: Run npm start (regenerate README + marketplace)"
if [ ! -d node_modules ]; then
    npm ci --silent 2>&1 | tail -2
fi
npm start --silent 2>&1 | tail -3
green "regeneration complete"

step "9: git status + commit (includes regenerated catalog)"
git add -A
git status --short
git commit -m "feat($TYPE): add $SLUG ($VERSION)  🤖🤖🤖

Source: https://github.com/RoninForge/roninforge-${SLUG}
Submitted via scripts/submit-to-awesome-copilot.sh

Generated with Claude Code.
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"

if [ "$DRY_RUN" -eq 1 ]; then
    green "DRY RUN: commit made locally on $BR. NOT pushing."
    echo ""
    echo "To inspect: cd $UPSTREAM && git show HEAD"
    exit 0
fi

step "10: Push branch to fork"
git push -u origin "$BR"

if [ "$NO_PR" -eq 1 ]; then
    green "Branch pushed. PR creation skipped (--no-pr)."
    echo ""
    echo "Open PR manually at:"
    echo "  https://github.com/github/awesome-copilot/compare/staged...RoninForge:$BR?expand=1"
    exit 0
fi

step "11: Open PR (base: staged, NEVER main)"

PR_TITLE="feat(${TYPE}): add ${SLUG}  🤖🤖🤖"
PR_BODY=$(cat <<EOF
## What this adds

\`${DST}\`

${SLUG} - $(read_meta description | head -c 500)

## Source-of-truth repo

Authored at \`github.com/RoninForge/roninforge-${SLUG}\`. The dist/ subtree of
that repo is byte-identical to what landed in this PR.

## Checklist

- [x] Targets \`staged\` branch (NOT \`main\`)
- [x] Branch was cut from \`upstream/staged\` (NOT from \`main\`)
- [x] \`npm start\` run; README + marketplace regenerated
- [x] No CRLF line endings (eng/fix-line-endings.sh clean)
- [x] codespell clean (or warnings explainable)
- [x] Naming convention: lowercase-kebab
- [x] Frontmatter required fields present
- [x] No symlinks
- [x] Validated locally with scripts/validate-awesome-copilot-submission.sh

## Generated-by-AI disclosure

Authored with Claude Code (Opus 4.7) by a human in the loop. Fast-track marker
appended to title per CONTRIBUTING.md.

🤖🤖🤖
EOF
)

PR_URL=$(gh pr create \
    --repo github/awesome-copilot \
    --base staged \
    --head "RoninForge:$BR" \
    --title "$PR_TITLE" \
    --body "$PR_BODY" 2>&1 | tail -1)

green "PR opened: $PR_URL"
echo ""
echo "Expected merge ETA: 1-3 days (median from n=19 recent new-submission PRs)."
echo "Watch for these failure labels in the next hour:"
echo "  - branched-main      (branch was cut from main, not staged)"
echo "  - targets-main       (base ref wrong)"
echo "  - skill-check-error  (skill-validator failed)"
