#!/bin/bash
# Recreate symlinks from monorepo root to uwz/claude/
# Run from monorepo root after branch switches clobber them.

MONOREPO="/home/zik/programming/uwz/monorepo"
CLAUDE_DIR="/home/zik/programming/uwz/claude"

cd "$MONOREPO" || exit 1

for target in .claude CLAUDE.md docs archive; do
  if [ -L "$target" ]; then
    continue
  fi
  if [ -e "$target" ]; then
    echo "WARNING: $target exists but is not a symlink — skipping"
    continue
  fi
  ln -s "$CLAUDE_DIR/$target" "$target"
  echo "Created symlink: $target -> $CLAUDE_DIR/$target"
done
