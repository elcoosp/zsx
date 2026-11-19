#!/usr/bin/env bash
set -euo pipefail

git reset HEAD -- . >/dev/null 2>&1 || true

commit_file() {
    local file="$1"
    shift

    if [[ -n $(git status --porcelain -- "$file" 2>/dev/null) ]]; then
        git add "$file"
        git commit "$@"
        echo "✅ Committed: $file"
    else
        echo "⏭️  Skipped: $file (no changes)"
    fi
}

commit_group() {
    local files=()
    while [[ "$1" != "--" ]]; do
        files+=("$1")
        shift
    done
    shift

    local has_changes=false
    for f in "${files[@]}"; do
        if [[ -n $(git status --porcelain -- "$f" 2>/dev/null) ]]; then
            has_changes=true
            break
        fi
    done

    if $has_changes; then
        for f in "${files[@]}"; do
            git add "$f"
        done
        git commit "$@"
        echo "✅ Committed group: ${files[*]}"
    else
        echo "⏭️  Skipped group (no changes)"
    fi
}

# ─── Documentation & Release Metadata ─────────────────────────────

commit_group \
  "docs/adr/0003-scope-aware-codegen.md" \
  "docs/adr/0004-event-handlers-v1.md" \
  "docs/adr/0005-component-prop-registry.md" \
  "docs/adr/0006-addviews-directory-discovery.md" \
  -- \
  -m "docs(adr): add ADRs 0003–0006 for M2 codegen, events, props, and discovery" \
  -m "Document architectural decisions for scope-aware codegen, event handlers v1,
component prop registry, and addViews directory discovery."

commit_group "docs/rfc/0001-markup-grammar.md" "docs/spec/grammar.ebnf" -- \
  -m "docs(rfc): add RFC-0001 markup grammar v1 and normative EBNF" \
  -m "Specify v1 block boundaries, productions, semantics S1-S8, diagnostic codes,
and recovery rules."

commit_file "docs/STATE.md" \
  -m "docs: update STATE.md for M1 slices and M2 codegen milestone" \
  -m "Record completed work packages, closed findings F1-F7, and remaining M2 items."

commit_file "AGENTS.md" \
  -m "docs: update AGENTS.md module map and fuzz commands" \
  -m "Document cst, astdump, fuzz, spec corpora, and zig build fuzz command."

commit_file "CHANGELOG.md" \
  -m "docs: add 0.4.0 release notes to CHANGELOG.md" \
  -m "Summarize M1 front-end slices, M2 codegen fixes, CLI additions, and RFC-0001."

commit_file "README.md" \
  -m "docs: update README.md for v0.4.0 features and CLI flags" \
  -m "Document directory discovery, event expressions, prop validation, cost
guardrails, and zsx migrate."

commit_group "VERSION" "build.zig.zon" -- \
  -m "chore(release): bump version to 0.4.0" \
  -m "Update VERSION and build.zig.zon to 0.4.0."

commit_file "commit.sh" \
  -m "chore: add automated conventional commit script" \
  -m "Add commit.sh helper for atomic file-by-file conventional commits."

echo ""
echo "🎉 Done. $(git log --oneline -10 | wc -l | tr -d ' ') recent commits."
git log --oneline -10
