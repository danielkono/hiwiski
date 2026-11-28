#!/usr/bin/env bash
# The version of the commit checked out, from the tags -- the only place a version is
# kept.
#
#   tool/version.sh            2026.1.1                 on a release tag v2026.1.1
#                              2026.2.0-rc.2            on a release candidate tag v2026.2.0-rc.2
#                              2026.2.0-rc.2.3.gabc1234 three commits after it
#                              2026.2.0-dev.3.gabc1234  three commits after v2026.2.0-dev
#   tool/version.sh --numeric  2026.1.1 / 2026.2.0      for iOS, which takes only numbers
#
# A release tag on the commit wins over every other tag. Otherwise the version comes
# from the highest dev or candidate tag in the commit's history -- the highest, not the
# nearest: main takes in every release branch, with its candidate tags, and those can be
# fewer commits away than main's own dev tag for the version after. Of the same
# version, a candidate tag outranks the dev tag. Without a dev or candidate tag ahead
# of the latest release, the next intermediate build would carry the released version
# again -- that stops here instead of at Apple.
set -euo pipefail

numeric=false
if [[ "${1:-}" == "--numeric" ]]; then
  numeric=true
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--numeric]" >&2
  exit 2
fi

release_pattern='^v[0-9]+\.[0-9]+\.[0-9]+$'

# On a release tag: that is the version.
release=$(git tag --points-at HEAD | grep -E "$release_pattern" | sort -V | tail -n 1 || true)
if [[ -n "$release" ]]; then
  echo "${release#v}"
  exit 0
fi

# Every dev and candidate tag in HEAD's history as "year minor patch kind candidate
# tag" -- a dev tag of kind 0, a candidate of kind 1 -- so that a numeric sort puts the
# highest last. The order is spelled out rather than left to sort -V, which knows
# nothing of a candidate outranking a dev tag; it would only sort the letters.
tag=$(git tag --merged HEAD | sed -nE \
  -e 's/^(v([0-9]+)\.([0-9]+)\.([0-9]+)-dev)$/\2 \3 \4 0 0 \1/p' \
  -e 's/^(v([0-9]+)\.([0-9]+)\.([0-9]+)-rc\.([0-9]+))$/\2 \3 \4 1 \5 \1/p' |
  sort -n -k1,1 -k2,2 -k3,3 -k4,4 -k5,5 | tail -n 1 | cut -d ' ' -f 6)
if [[ -z "$tag" ]]; then
  echo "error: no dev tag (v<version>-dev) or release candidate tag before this commit -- set one" >&2
  exit 1
fi
name=${tag#v}
base=${name%%-*}

# The tag has to be ahead of every release before HEAD.
latest_release=$(git tag --merged HEAD | grep -E "$release_pattern" | sort -V | tail -n 1 || true)
if [[ -n "$latest_release" ]]; then
  released=${latest_release#v}
  if [[ "$(printf '%s\n%s\n' "$released" "$base" | sort -V | tail -n 1)" == "$released" ]]; then
    echo "error: $latest_release is released, but the latest dev or candidate tag is $tag --" \
      "set the next one, e.g. git tag v<next>-dev" >&2
    exit 1
  fi
fi

distance=$(git rev-list --count "$tag..HEAD")
if $numeric; then
  echo "$base"
elif [[ "$name" == *-rc.* && "$distance" == 0 ]]; then
  echo "$name"
else
  echo "$name.$distance.g$(git rev-parse --short=7 HEAD)"
fi
