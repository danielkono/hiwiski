#!/usr/bin/env bash
# CHANGELOG.md, where every branch says what it does.
#
#   tool/changelog.sh candidate 2026.2.0       Unreleased becomes the release candidate 2026.2.0
#   tool/changelog.sh release 2026.2.0         the candidate becomes the release, with today's date
#   tool/changelog.sh notes 2026.2.0[-rc.1]    that version's section, for its GitHub release
#   tool/changelog.sh take 2026.2.0 <file>     that version's section as <file> has it, here
#   tool/changelog.sh check <from> <to>        every feat/ or fix/ branch merged in between
#                                              touched the changelog (CI on main and release/…)
#
# A version's section goes through two headings: `## 2026.2.0 — Release candidate
# {#2026.2.0}` from the start of its release branch, then `## 2026.2.0 — <date>
# {#2026.2.0}` from its release. The website shows the first under "Preview" and the
# second under "What's new"; the anchor stays the version all along, so a link to it
# keeps working.
set -euo pipefail

file="$(dirname "$0")/../CHANGELOG.md"
version_pattern='^[0-9]+\.[0-9]+\.[0-9]+$'
candidate_pattern='^[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$'
candidate_label='Release candidate'

usage() {
  echo "usage:" >&2
  sed -n '4,9p' "$0" | sed 's/^#//' >&2
  exit 2
}

# The lines of a section, without its heading: the one whose heading starts with
# `## <version> — <label>`, or with `## <version> — ` and a date when the label is
# `date`. Empty if there is none.
section() { # version label
  awk -v prefix="## $1 — " -v label="$2" '
    inside && /^## / { exit }
    inside { print; next }
    index($0, prefix) == 1 {
      rest = substr($0, length(prefix) + 1)
      inside = (label == "date") ? (rest ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] /) \
                                 : (index(rest, label " ") == 1)
    }
  ' "$file"
}

blank() { [[ -z "${1//[[:space:]]/}" ]]; }

case "${1:-}" in
  candidate)
    version="${2:-}"
    [[ "$version" =~ $version_pattern ]] || usage
    if grep -qE "^## ${version//./\\.} " "$file"; then
      echo "$version is in the changelog already." >&2
      exit 1
    fi
    # What is under Unreleased now belongs to the candidate; Unreleased starts empty.
    # For a patch it is empty already: the fixes then go into the candidate's section.
    awk -v heading="## $version — $candidate_label {#$version}" '
      !done && /^## Unreleased$/ { print; print ""; print heading; done = 1; next }
      { print }
    ' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
    ;;
  release)
    version="${2:-}"
    [[ "$version" =~ $version_pattern ]] || usage
    heading="## $version — $candidate_label {#$version}"
    if ! grep -qxF "$heading" "$file"; then
      echo "$version is no release candidate in the changelog -- every release is one first" \
        "(tool/release.sh candidate $version)." >&2
      exit 1
    fi
    if blank "$(section "$version" "$candidate_label")"; then
      echo "The candidate $version says nothing in the changelog." >&2
      exit 1
    fi
    awk -v candidate="$heading" -v heading="## $version — $(date +%Y-%m-%d) {#$version}" '
      $0 == candidate { print heading; next }
      { print }
    ' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
    ;;
  notes)
    version="${2:-}"
    # A candidate's notes are its version's section while it is still a candidate; a
    # release's are the section once it carries its date. A tag pushed before
    # `tool/changelog.sh release` stops here instead of publishing the candidate's
    # heading as the release's.
    if [[ "$version" =~ $candidate_pattern ]]; then
      notes=$(section "${version%%-*}" "$candidate_label")
    elif [[ "$version" =~ $version_pattern ]]; then
      notes=$(section "$version" date)
    else
      usage
    fi
    if blank "$notes"; then
      echo "No notes for $version in the changelog." >&2
      exit 1
    fi
    printf '%s\n' "$notes"
    ;;
  take)
    # For a release branch merged into main (tool/release.sh). The branch writes only
    # its own version's section, and main's entries for the version after lie right
    # above it, so git sees a conflict where nothing contradicts. Here the section comes
    # from the branch and everything else stays: in place of main's copy of the
    # section, or, the first time a patch comes in, above the first lower version.
    version="${2:-}"
    from="${3:-}"
    [[ "$version" =~ $version_pattern && -f "$from" ]] || usage
    awk -v prefix="## $version — " -v version="$version" -v from="$from" '
      function cmp(a, b,    x, y, i) {
        split(a, x, "."); split(b, y, ".")
        for (i = 1; i <= 3; i++) if (x[i] + 0 != y[i] + 0) return x[i] + 0 < y[i] + 0 ? -1 : 1
        return 0
      }
      BEGIN {
        while ((getline line < from) > 0) {
          if (inside && line ~ /^## /) break
          if (index(line, prefix) == 1) inside = 1
          if (inside) section = section line "\n"
        }
        if (section == "") {
          print "No section " version " in " from "." > "/dev/stderr"
          failed = 1
          exit 1
        }
      }
      skipping && /^## / { skipping = 0 }
      skipping { next }
      !done && index($0, prefix) == 1 { printf "%s", section; done = 1; skipping = 1; next }
      !done && /^## [0-9]+\.[0-9]+\.[0-9]+ — / {
        v = substr($0, 4)
        sub(/ .*/, "", v)
        if (cmp(v, version) < 0) { printf "%s", section; done = 1 }
      }
      { print }
      END { if (!failed && !done) printf "\n%s", section }
    ' "$file" > "$file.tmp" || {
      rm -f "$file.tmp"
      exit 1
    }
    mv "$file.tmp" "$file"
    ;;
  check)
    from="${2:-}"
    to="${3:-}"
    [[ -n "$from" && -n "$to" ]] || usage
    missing=0
    # Branches are merged with a merge commit ("Merge branch 'feat/…'", on a release
    # branch "… into release/…"); a branch is the merge's second parent, what it
    # changed the diff against the first.
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
