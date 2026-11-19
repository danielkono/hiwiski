#!/usr/bin/env bash
# Comments explain their reason in place. This fails when the repository points at
# documents it does not contain: the old specification's chapters (`06-sync.md`),
# decision numbers (`D29`, `Decision 32`), project phases (`P4`) or review findings.
# Flyway migrations are left out: they are never edited, so what they say stays.
#
#   tool/check_references.sh     (from the repository root; CI runs it)
set -euo pipefail

pattern='(\b[0-9]{2}-[a-z-]+\.md\b|\bspec/[0-9]|\bDecisions? [0-9]+\b|\bD[0-9]{1,2}\b|\b(acceptance case|first run) (from|of) P[0-9]\b|\b[Ss]ecurity review [0-9]{4}|\breviews/|\bthe POC\b|STATUS\.md|mvvm-migration\.md|public-server\.md)'

hits=$(git grep -n -I -P "$pattern" -- . \
  ':!server/db/src/main/resources/db/migration/' \
  ':!tool/check_references.sh' \
  ':!**/*.lock' ':!**/*.xib' || true)

if [[ -n "$hits" ]]; then
  echo "References to documents outside the repository -- say the reason in place:"
  echo "$hits"
  exit 1
fi
