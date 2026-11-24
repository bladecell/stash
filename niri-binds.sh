#!/bin/sh
# Writes Stash's global binds to <niri dir>/stash-binds.kdl and includes it from config.kdl.
# Keys already bound elsewhere are skipped. Rolls back if `niri validate` rejects the result.
# Usage: niri-binds.sh [slot-modifier] [cycle-key] [niri-config-dir]
#   slot-modifier default Mod+Alt; cycle-key default Mod+C, "none" to skip
mod=${1:-Mod+Alt}
cyc=${2:-Mod+C}
case $mod in *[!A-Za-z+_]*|"") echo "Invalid modifier: $mod"; exit 1;; esac
case $cyc in *[!A-Za-z0-9+_]*|"") echo "Invalid key: $cyc"; exit 1;; esac
mod=${mod%+}
dir=${3:-${XDG_CONFIG_HOME:-$HOME/.config}/niri}
cfg=$dir/config.kdl
out=$dir/stash-binds.kdl
[ -f "$cfg" ] || { echo "No niri config at $cfg"; exit 1; }

bak=$(mktemp -d)
cp "$cfg" "$bak/config.kdl"
[ -f "$out" ] && cp "$out" "$bak/stash-binds.kdl"

taken() {  # is this key bound in any other niri config file?
  grep -rqsiE "^[[:space:]]*$1[[:space:]]+[^/]*\{" "$dir" --include='*.kdl' --exclude=stash-binds.kdl
}

skipped=""
{
  echo "// Written by the Stash DMS plugin (Settings → Write niri binds). Rewriting replaces this file."
  echo "binds {"
  if taken 'Mod\+V'; then skipped="$skipped Mod+V"
  else echo '    Mod+V hotkey-overlay-title="Stash" { spawn "dms" "ipc" "call" "stash" "toggle"; }'; fi
  if [ "$cyc" != none ]; then
    if taken "$(printf %s "$cyc" | sed 's/+/\\+/g')"; then skipped="$skipped $cyc"
    else echo "    $cyc hotkey-overlay-title=\"Stash: copy next older entry\" { spawn \"dms\" \"ipc\" \"call\" \"stash\" \"cycle\"; }"; fi
  fi
  for i in 1 2 3 4 5 6 7 8 9; do
    if taken "$(printf %s "$mod" | sed 's/+/\\+/g')\+$i"; then skipped="$skipped $mod+$i"
    else echo "    $mod+$i hotkey-overlay-title=\"Stash: paste slot $i\" { spawn \"dms\" \"ipc\" \"call\" \"stash\" \"pasteSlot\" \"$i\"; }"; fi
  done
  echo "}"
} > "$out"

grep -qs '^include "stash-binds.kdl"' "$cfg" || printf '\ninclude "stash-binds.kdl"\n' >> "$cfg"

if ! err=$(niri validate -c "$cfg" 2>&1); then
  cp "$bak/config.kdl" "$cfg"
  if [ -f "$bak/stash-binds.kdl" ]; then cp "$bak/stash-binds.kdl" "$out"; else rm -f "$out"; fi
  rm -rf "$bak"
  echo "niri rejected the binds; nothing changed."
  echo "$err" | grep -iv "^\s*$" | tail -5
  exit 1
fi
rm -rf "$bak"
echo "Wrote $out${skipped:+ (already bound elsewhere, skipped:$skipped)}"
