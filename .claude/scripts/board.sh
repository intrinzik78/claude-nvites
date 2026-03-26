#!/usr/bin/env bash
# board.sh — Orchestration board. Zero API cost, zero subagents.
# Run from anywhere: bash .claude/scripts/board.sh

set -euo pipefail

MONOREPO="/home/zik/programming/uwz/monorepo"
WORKTREES="/home/zik/programming/uwz/worktrees"
HANDOFFS="$MONOREPO/handoffs"

# Colors
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
RESET='\033[0m'

divider() {
    echo -e "${DIM}$(printf '%.0s─' {1..60})${RESET}"
}

# ── 1. Worktree State ──────────────────────────────────────────
echo -e "\n${BOLD}${CYAN}WORKTREE STATE${RESET}"
divider

if [ -d "$WORKTREES" ]; then
    for wt in "$WORKTREES"/*/; do
        [ -d "$wt" ] || continue
        name=$(basename "$wt")

        # Commits ahead/behind dev
        ahead=$(git -C "$wt" rev-list dev..HEAD 2>/dev/null | wc -l)
        behind=$(git -C "$wt" rev-list HEAD..dev 2>/dev/null | wc -l)

        # Dirty files
        dirty=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l)

        # Branch
        branch=$(git -C "$wt" branch --show-current 2>/dev/null || echo "detached")

        # Status color
        if [ "$dirty" -gt 0 ]; then
            status_color="$YELLOW"
            dirty_tag=" ${YELLOW}(${dirty} dirty)${RESET}"
        else
            status_color="$GREEN"
            dirty_tag=""
        fi

        echo -e "  ${status_color}${name}${RESET} [${branch}]  +${ahead}/-${behind}${dirty_tag}"
    done
else
    echo -e "  ${DIM}No worktrees directory found${RESET}"
fi

# ── 2. Active Dispatches ───────────────────────────────────────
echo -e "\n${BOLD}${CYAN}ACTIVE DISPATCHES${RESET}"
divider

found_dispatch=0

# Check monorepo root
if [ -f "$MONOREPO/DISPATCH.md" ]; then
    title=$(head -1 "$MONOREPO/DISPATCH.md" | sed 's/^# //')
    date=$(grep -m1 '^\*\*Date:\*\*' "$MONOREPO/DISPATCH.md" | sed 's/\*\*Date:\*\* //' || echo "unknown")
    echo -e "  ${YELLOW}dev${RESET}: ${title} ${DIM}(${date})${RESET}"
    found_dispatch=1
fi

# Check worktrees
if [ -d "$WORKTREES" ]; then
    for wt in "$WORKTREES"/*/; do
        [ -d "$wt" ] || continue
        if [ -f "$wt/DISPATCH.md" ]; then
            name=$(basename "$wt")
            title=$(head -1 "$wt/DISPATCH.md" | sed 's/^# //')
            date=$(grep -m1 '^\*\*Date:\*\*' "$wt/DISPATCH.md" | sed 's/\*\*Date:\*\* //' || echo "unknown")

            # Staleness check (>3 days)
            if [ "$date" != "unknown" ]; then
                dispatch_epoch=$(date -d "$date" +%s 2>/dev/null || echo 0)
                now_epoch=$(date +%s)
                age_days=$(( (now_epoch - dispatch_epoch) / 86400 ))
                if [ "$age_days" -gt 3 ]; then
                    stale_tag=" ${RED}STALE (${age_days}d)${RESET}"
                else
                    stale_tag=""
                fi
            else
                stale_tag=""
            fi

            echo -e "  ${YELLOW}${name}${RESET}: ${title} ${DIM}(${date})${RESET}${stale_tag}"
            found_dispatch=1
        fi
    done
fi

if [ "$found_dispatch" -eq 0 ]; then
    echo -e "  ${DIM}No active dispatches${RESET}"
fi

# ── 3. Recent Handoffs (last 3 days) ──────────────────────────
echo -e "\n${BOLD}${CYAN}RECENT HANDOFFS (3 days)${RESET}"
divider

found_handoff=0
cutoff=$(date -d "3 days ago" +%Y-%m-%d 2>/dev/null || date -v-3d +%Y-%m-%d 2>/dev/null || echo "0000-00-00")

if [ -d "$HANDOFFS" ]; then
    for domain in "$HANDOFFS"/*/; do
        [ -d "$domain" ] || continue
        domain_name=$(basename "$domain")

        # Find handoffs newer than cutoff
        recent=""
        for f in "$domain"*.md; do
            [ -f "$f" ] || continue
            fname=$(basename "$f")
            [ "$fname" = ".gitkeep" ] && continue
            # Extract date from filename (YYYY-MM-DD-slug.md)
            fdate=${fname:0:10}
            if [[ "$fdate" > "$cutoff" || "$fdate" == "$cutoff" ]]; then
                title=$(head -1 "$f" | sed 's/^# //')
                recent="${recent}\n    ${DIM}${fdate}${RESET} ${title}"
                found_handoff=1
            fi
        done

        if [ -n "$recent" ]; then
            echo -e "  ${GREEN}${domain_name}${RESET}${recent}"
        fi
    done
fi

if [ "$found_handoff" -eq 0 ]; then
    echo -e "  ${DIM}No handoffs in the last 3 days${RESET}"
fi

# ── 4. Bookmarks (NEXT.md item counts) ────────────────────────
echo -e "\n${BOLD}${CYAN}BOOKMARKS${RESET}"
divider

# Root NEXT.md
if [ -f "$MONOREPO/NEXT.md" ]; then
    count=$(grep -c '^\s*[-*] ' "$MONOREPO/NEXT.md" 2>/dev/null) || count=0
    echo -e "  ${GREEN}dev${RESET}: ${count} items"
else
    echo -e "  ${DIM}dev: no NEXT.md${RESET}"
fi

# Worktree NEXT.md files
if [ -d "$WORKTREES" ]; then
    for wt in "$WORKTREES"/*/; do
        [ -d "$wt" ] || continue
        name=$(basename "$wt")
        if [ -f "$wt/NEXT.md" ]; then
            count=$(grep -c '^\s*[-*] ' "$wt/NEXT.md" 2>/dev/null) || count=0
            echo -e "  ${GREEN}${name}${RESET}: ${count} items"
        else
            echo -e "  ${DIM}${name}: no NEXT.md${RESET}"
        fi
    done
fi

# ── 5. Dependency Signals ─────────────────────────────────────
echo -e "\n${BOLD}${CYAN}DEPENDENCY SIGNALS${RESET}"
divider

found_dep=0

# Scan all DISPATCH.md files for BLOCKED/BLOCKING lines
for dispatch_file in "$MONOREPO/DISPATCH.md" "$WORKTREES"/*/DISPATCH.md; do
    [ -f "$dispatch_file" ] || continue
    name=$(basename "$(dirname "$dispatch_file")")
    [ "$name" = "monorepo" ] && name="dev"

    blocked=$(grep -i '^\s*-\s*BLOCKED:' "$dispatch_file" 2>/dev/null || true)
    blocking=$(grep -i '^\s*-\s*BLOCKING:' "$dispatch_file" 2>/dev/null || true)

    if [ -n "$blocked" ] || [ -n "$blocking" ]; then
        echo -e "  ${YELLOW}${name}${RESET}"
        [ -n "$blocked" ] && echo -e "    ${RED}${blocked}${RESET}"
        [ -n "$blocking" ] && echo -e "    ${YELLOW}${blocking}${RESET}"
        found_dep=1
    fi
done

if [ "$found_dep" -eq 0 ]; then
    echo -e "  ${DIM}No dependency signals${RESET}"
fi

echo ""
