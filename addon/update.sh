#!/bin/sh
# CraftPath updater for macOS / Linux - keeps the addon's price data fresh.
#
# WoW addons cannot go online, so this downloads the latest Data.lua from the website into
# AddOns/CraftPath. In game, type /reload to load the new numbers.
#
#   One update now:            curl -fsSL __BASE__/addon/update.sh | sh
#   Every 30 minutes (cron):   curl -fsSL __BASE__/addon/update.sh | sh -s -- --install
#   Custom AddOns folder:      ... | sh -s -- --addons "/path/to/_forever_/Interface/AddOns"

BASE="__BASE__"
QUERY="__QUERY__"
ADDONS=""
INSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --addons) ADDONS="$2"; shift 2 ;;
    --install) INSTALL=1; shift ;;
    *) shift ;;
  esac
done

if [ -z "$ADDONS" ]; then
  for d in "/Applications/World of Warcraft/_forever_/Interface/AddOns" "$HOME/Applications/World of Warcraft/_forever_/Interface/AddOns" \
           "$HOME/Games/world-of-warcraft/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"; do
    if [ -d "$d" ]; then ADDONS="$d"; break; fi
  done
fi
if [ -z "$ADDONS" ] || [ ! -d "$ADDONS" ]; then
  echo "Could not find World of Warcraft/_forever_/Interface/AddOns. Use --addons \"/path/to/AddOns\"."
  exit 1
fi

set -e
if [ ! -f "$ADDONS/CraftPath/CraftPath.toc" ]; then
  echo "Installing CraftPath into $ADDONS ..."
  tmpzip="$(mktemp)"
  curl -fsSL "$BASE/addon/CraftPath.zip$QUERY" -o "$tmpzip"
  unzip -oq "$tmpzip" -d "$ADDONS"
  rm -f "$tmpzip"
else
  tmp="$(mktemp)"
  curl -fsSL "$BASE/addon/Data.lua$QUERY" -o "$tmp"
  if head -n 1 "$tmp" | grep -q "^-- CraftPath data"; then
    mv "$tmp" "$ADDONS/CraftPath/Data.lua"
  else
    rm -f "$tmp"; echo "Unexpected download - Data.lua was not replaced."; exit 1
  fi
fi
echo "$(date +%H:%M)  CraftPath data updated. Type /reload in game to load it."

if [ "$INSTALL" = "1" ]; then
  mkdir -p "$HOME/.craftpath"
  curl -fsSL "$BASE/addon/update.sh$QUERY" -o "$HOME/.craftpath/update.sh"
  chmod +x "$HOME/.craftpath/update.sh"
  line="*/30 * * * * /bin/sh \"$HOME/.craftpath/update.sh\" --addons \"$ADDONS\" >/dev/null 2>&1"
  ( crontab -l 2>/dev/null | grep -v "craftpath/update.sh"; echo "$line" ) | crontab -
  echo "Done. CraftPath data updates every 30 minutes (crontab -e to remove)."
fi
