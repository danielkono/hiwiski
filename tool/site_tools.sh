#!/usr/bin/env bash
# Hugo and Pagefind for building the website in CI, at fixed
# versions, from their GitHub releases. Each archive is checked against a SHA-256 kept
# here, not against the checksum file next to it: a release whose assets were replaced
# would bring a matching checksum along. The binaries run in the release's
# `site-build` job, which builds the site and cannot push; `site-image` pushes it.
# Installed into the directory given (on the PATH afterwards).
#
# A new version: its new SHA-256 too -- from the release's checksum file, compared
# with the archive downloaded on its own.
#
#   tool/site_tools.sh "$RUNNER_TEMP/bin"
#
# Linux x86_64 only: that is where CI runs. Locally, Hugo comes from Homebrew and
# Pagefind is not needed -- a local build has no search.
set -euo pipefail

readonly HUGO_VERSION=0.168.0
readonly HUGO_SHA256=787f100057328824f38c6ad7c87ff10d6451ae0a7bc39cedaad0dd2bcde17e53
readonly PAGEFIND_VERSION=1.4.0
readonly PAGEFIND_SHA256=8737736d3450c3e0a497233324716e95e4d0119c4aacac9361f339968b24dc79

bin="${1:?usage: $0 <directory>}"
mkdir -p "$bin"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

fetch() { curl --fail --silent --show-error --location --output "$2" "$1"; }
verify() { # file sha256
  echo "$2  $1" | sha256sum --check --status || {
    echo "$1 does not match the SHA-256 in $0" >&2
    exit 1
  }
}

hugo="hugo_extended_${HUGO_VERSION}_linux-amd64.tar.gz"
fetch "https://github.com/gohugoio/hugo/releases/download/v$HUGO_VERSION/$hugo" "$hugo"
verify "$hugo" "$HUGO_SHA256"
tar -xzf "$hugo" hugo
install -m 755 hugo "$bin/hugo"

pagefind="pagefind-v$PAGEFIND_VERSION-x86_64-unknown-linux-musl.tar.gz"
fetch "https://github.com/CloudCannon/pagefind/releases/download/v$PAGEFIND_VERSION/$pagefind" "$pagefind"
verify "$pagefind" "$PAGEFIND_SHA256"
tar -xzf "$pagefind" pagefind
install -m 755 pagefind "$bin/pagefind"

"$bin/hugo" version
"$bin/pagefind" --version
