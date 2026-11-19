#!/usr/bin/env bash
# Every page of the website exists in both languages:
# Hugo has no fallback, and a page missing in one tree would simply not exist there.
set -eu
cd "$(dirname "$0")/../site/content"
pages() { (cd "$1" && find . -name '*.md' | sort); }
if ! diff -u --label de --label en <(pages de) <(pages en); then
  echo "The German and the English pages differ (above)." >&2
  exit 1
fi
