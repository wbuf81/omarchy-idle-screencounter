#!/usr/bin/env bash

# Copy this working tree into Omarchy's user-plugin directory and make the
# shell rescan it. Omarchy intentionally rejects plugin symlinks, so copying
# is the safe, supported local-development workflow.
set -euo pipefail

plugin_id="io.github.wbuf81.idle-screencounter"
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="$HOME/.config/omarchy/plugins/$plugin_id"
enable=false

if [[ ${1:-} == "--enable" ]]; then
  enable=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--enable]" >&2
  exit 2
fi

omarchy plugin validate "$source_dir"
mkdir -p "$target_dir"
rsync -a --delete --exclude '.git/' --exclude '.gitignore' "$source_dir/" "$target_dir/"
omarchy-shell shell rescanPlugins

if "$enable"; then
  omarchy plugin enable "$plugin_id" --section right
fi

echo "Synced $plugin_id. Edit the repository, then run scripts/dev-sync.sh again."
