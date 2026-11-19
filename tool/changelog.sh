#!/usr/bin/env bash
# CHANGELOG.md, where every branch says what it does.
#
#   tool/changelog.sh release 2026.1.0   Unreleased becomes the version; commit, then tag
#   tool/changelog.sh notes 2026.1.0     that version's section, for its GitHub release
#   tool/changelog.sh check <from> <to>  every feat/ or fix/ branch merged in between
#                                        touched the changelog (CI on main)
set -euo pipefail

file="$(dirname "$0")/../CHANGELOG.md"
version_pattern='^[0-9]+\.[0-9]+\.[0-9]+$'

usage() {
  echo "usage:" >&2
  sed -n '4,7p' "$0" | sed 's/^#//' >&2
  exit 2
}

case "${1:-}" in
  release)
    version="${2:-}"
    [[ "$version" =~ $version_pattern ]] || usage
    if grep -qE "^## ${version//./\\.} " "$file"; then
      echo "$version is in the changelog already." >&2
      exit 1
    fi
    # What is under Unreleased now belongs to the version; Unreleased starts empty.
    # The anchor is the version, so the app and the site can link to it.
    awk -v heading="## $version — $(date +%Y-%m-%d) {#$version}" '
      !done && /^## Unreleased$/ { print; print ""; print heading; done = 1; next }
      { print }
    ' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
    ;;
  notes)
    version="${2:-}"
    [[ "$version" =~ $version_pattern ]] || usage
    notes=$(awk -v version="$version" '
      $0 ~ "^## " version " " { inside = 1; next }
      inside && /^## / { exit }
      inside { print }
    ' "$file")
    if [[ -z "${notes//[[:space:]]/}" ]]; then
      echo "No notes for $version in the changelog." >&2
      exit 1
    fi
    printf '%s\n' "$notes"
    ;;
  check)
    from="${2:-}"
    to="${3:-}"
    [[ -n "$from" && -n "$to" ]] || usage
    missing=0
    # Branches are merged with a merge commit ("Merge branch 'feat/…'"); a branch is
    # the merge's second parent, what it changed the diff against the first.
    while read -r merge subject; do
      branch=$(sed -nE "s/^Merge branch '([^']+)'.*/\1/p" <<< "$subject")
      [[ "$branch" =~ ^(feat|fix)/ ]] || continue
      if ! git diff --name-only "$merge^1" "$merge" | grep -qx CHANGELOG.md; then
        echo "$branch ($merge) does not say in CHANGELOG.md what it does." >&2
        missing=1
      fi
    done < <(git log --merges --first-parent --format='%h %s' "$from..$to")
    exit "$missing"
    ;;
  *)
    usage
    ;;
esac
