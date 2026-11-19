#!/usr/bin/env bash
# The version of the commit checked out, from the tags -- the only place a version is
# kept.
#
#   tool/version.sh            2026.1.1               on a release tag v2026.1.1
#                              2026.2.0-dev.3.gabc1234 three commits after v2026.2.0-dev
#   tool/version.sh --numeric  2026.1.1 / 2026.2.0    for iOS, which takes only numbers
#
# A release tag on the commit wins over a dev tag on the same commit. Without a dev tag
# after the latest release, the next intermediate build would carry the released
# version again -- that stops here instead of at Apple.
set -euo pipefail

numeric=false
if [[ "${1:-}" == "--numeric" ]]; then
  numeric=true
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--numeric]" >&2
  exit 2
fi

release_pattern='^v[0-9]+\.[0-9]+\.[0-9]+$'
dev_pattern='^v[0-9]+\.[0-9]+\.[0-9]+-dev$'

# On a release tag: that is the version.
release=$(git tag --points-at HEAD | grep -E "$release_pattern" | sort -V | tail -n 1 || true)
if [[ -n "$release" ]]; then
  echo "${release#v}"
  exit 0
fi

# Otherwise: the nearest dev tag, and how far HEAD is from it.
if ! described=$(git describe --tags --long --abbrev=7 --match 'v*-dev' 2>/dev/null); then
  echo "error: no dev tag (v<version>-dev) before this commit -- set one" >&2
  exit 1
fi
# v2026.2.0-dev-3-gabc1234
tag=${described%-*-g*}
rest=${described#"$tag"-}
distance=${rest%%-*}
commit=${rest#*-}
base=${tag#v}
base=${base%-dev}

# The dev tag has to be ahead of every release before HEAD.
latest_release=$(git tag --merged HEAD | grep -E "$release_pattern" | sort -V | tail -n 1 || true)
if [[ -n "$latest_release" ]]; then
  released=${latest_release#v}
  if [[ "$(printf '%s\n%s\n' "$released" "$base" | sort -V | tail -n 1)" == "$released" ]]; then
    echo "error: $latest_release is released, but the latest dev tag is $tag --" \
      "set the next one, e.g. git tag v<next>-dev" >&2
    exit 1
  fi
fi

if $numeric; then
  echo "$base"
else
  echo "$base-dev.$distance.$commit"
fi
