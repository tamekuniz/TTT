#!/bin/zsh
set -euo pipefail

DERIVED_DATA_PATH="${1:?derived data path is required}"
STATE_DIR="$DERIVED_DATA_PATH/BuildMetadata"
STATE_FILE="$STATE_DIR/build-number-state"
TODAY="$(date '+%Y%m%d')"

mkdir -p "$STATE_DIR"

last_date=""
last_index=-1

if [[ -f "$STATE_FILE" ]]; then
  IFS=' ' read -r stored_date stored_index < "$STATE_FILE" || true
  last_date="${stored_date:-}"
  last_index="${stored_index:--1}"
fi

if [[ "$last_date" == "$TODAY" ]]; then
  next_index=$((last_index + 1))
else
  next_index=0
fi

suffix_index=$next_index
suffix=""

while true; do
  remainder=$((suffix_index % 26))
  suffix_char=$(printf "\\$(printf '%03o' $((65 + remainder)))")
  suffix="${suffix_char}${suffix}"

  if (( suffix_index < 26 )); then
    break
  fi

  suffix_index=$((suffix_index / 26 - 1))
done

printf '%s %s\n' "$TODAY" "$next_index" > "$STATE_FILE"
printf '%s%s\n' "$TODAY" "$suffix"
