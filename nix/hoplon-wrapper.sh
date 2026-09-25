#!/usr/bin/env bash
# =============================================================================
# Hoplon Nix wrapper.
#
# The Nix store is read-only, but the Hoplon launcher writes into HOPLON_HOME
# (it uses $HOPLON_HOME/home as an isolated HOME and may seed node_modules next
# to the bundled binary). This wrapper builds a writable HOPLON_HOME under the
# user's XDG data directory: real directories for the parts opencode writes,
# symlinks to the store for the payload it only reads. It then execs a real
# copy of the launcher so `readlink -f` resolves HOPLON_HOME to the writable
# directory rather than to the store.
#
# HOPLON_STORE_DIR is set by wrapProgram at build time.
# =============================================================================
set -euo pipefail

store="${HOPLON_STORE_DIR:?HOPLON_STORE_DIR is not set (wrapProgram did not run)}"
data="${XDG_DATA_HOME:-${HOME:?HOME is not set}/.local/share}/hoplon"

mkdir -p "$data/bin" "$data/home"

# bin must be a real directory so opencode can create cache files beside the
# binary; the binary itself is a symlink into the immutable store.
ln -sfn "$store/bin/opencode" "$data/bin/opencode"

for entry in scripts config themes agents skills tui; do
  ln -sfn "$store/$entry" "$data/$entry"
done

ln -sfn "$store/AGENTS.md" "$data/AGENTS.md"
ln -sfn "$store/VERSION" "$data/VERSION"

# The launcher must be a real file: if it were a symlink, readlink -f would
# resolve it back into the store and HOPLON_HOME would be read-only.
cp -f "$store/hoplon" "$data/hoplon"
chmod 0755 "$data/hoplon"

exec "$data/hoplon" "$@"
