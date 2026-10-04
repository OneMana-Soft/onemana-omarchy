#!/usr/bin/env bash
# Everything that can be checked without a running Omarchy session, and the
# Omarchy checks when this is an Omarchy machine.
set -euo pipefail
dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$dir/manifest.json"
for s in connect open install-desktop install-local-ai validate.sh; do bash -n "$dir/scripts/$s"; done
command -v shellcheck >/dev/null 2>&1 && shellcheck "$dir"/scripts/*
node --test "$dir"/tests/*.test.js

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$dir"
  # Quickshell resolves `qs.*` to the shell folder; give qmllint the same map.
  lint=$(mktemp -d)
  ln -s "$OMARCHY_PATH/shell" "$lint/qs"
  out=$(qmllint -I "$lint" "$dir/OneCampState.qml" "$dir/OneCampRow.qml" "$dir/BarWidget.qml" 2>&1 || true)
  rm -rf "$lint"
  # Fail on what is a real mistake. The shell's style groups are untyped
  # QtObjects and Quickshell's process types are not exported to qmllint, so
  # [missing-property] on them and [signal-handler-parameters] are expected,
  # as in first-party and published plugins.
  if grep -E "\[(unqualified|unresolved-type|import|inheritance-cycle|incompatible-type)\]" <<<"$out"; then
    exit 1
  fi
fi
