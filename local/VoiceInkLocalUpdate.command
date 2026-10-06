#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
ROOT="$HOME/Developer/VoiceInk-local"
if [[ ! -x "$ROOT/local/update-voiceink.sh" ]]; then
    printf 'Updater source is missing: %s\n' "$ROOT"
    printf 'Restore the source from https://github.com/turnipsforme/VoiceInk before updating.\n'
    exit 1
fi
"$ROOT/local/update-voiceink.sh" --update
