#!/usr/bin/env bash
# Release branches and their candidates (docs/releasing.md). Nothing is pushed: every
# step ends by naming what to push.
#
#   tool/release.sh candidate 2026.2.0   release/2026.2.0 from main, which goes on towards 2026.3.0
#   tool/release.sh candidate 2026.2.1   release/2026.2.1 from the release v2026.2.0: a fix
#   tool/release.sh rc                   the next candidate tag, on the release branch checked out
#   tool/release.sh final                the release's commit, on the release branch checked out
#
# The branch is where the next version's number is decided. The version main works
# towards -- its dev tag -- or any above it starts from main, which then goes on towards
# the next minor version: the patch numbers after the candidate stay free for its
# fixes. A patch number below it is such a fix and starts from the release before it,
# so that nothing of main comes along.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  echo "usage:" >&2
  sed -n '5,8p' "$0" | sed 's/^#//' >&2
  exit 2
}
fail() {
  echo "error: $*" >&2
  exit 1
}
clean() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    fail "the working tree has changes -- commit or stash them first"
  fi
}
has_tag() { git rev-parse -q --verify "refs/tags/$1" > /dev/null; }
has_branch() { git rev-parse -q --verify "refs/heads/$1" > /dev/null; }
# Tags set on GitHub or on another machine count too.
fetch_tags() {
  git fetch --tags --quiet || echo "warning: git fetch --tags failed -- tags set elsewhere are not seen" >&2
}
# The contract as the version publishes it. From its first candidate on, apps and
# servers of the version are out there, so the baseline moves at the start of the
# branch and once more with the release, for what the fixes added in between.
baseline() { (cd server && ./gradlew --quiet :api:acceptSpecBaseline); }

# The version of the release branch checked out.
branch_version() {
  local branch
  branch=$(git symbolic-ref --short HEAD 2> /dev/null || true)
  [[ "$branch" =~ ^release/([0-9]+\.[0-9]+\.[0-9]+)$ ]] ||
    fail "not on a release branch (release/<version>)"
  echo "${BASH_REMATCH[1]}"
}

# Takes the release branch into main, so that its fixes are there too, and comes back
# to the branch. Two conflicts are expected and resolved here; any other is left to
# resolve by hand:
#
# - CHANGELOG.md: the branch writes only its own version's section, but main's entries
#   for the version after lie right against it, and git conflicts where nothing
#   contradicts. That section is the branch's, everything else main's.
# - The contract's baseline, when a patch moved it while main had moved it for a newer
#   candidate: main's is the newer contract and stays.
merge_into_main() { # version
  local branch=release/$1 theirs conflicts
  git switch --quiet main
  if ! git merge --quiet --no-ff --no-edit "$branch" > /dev/null; then
    git rev-parse -q --verify MERGE_HEAD > /dev/null || fail "could not merge $branch into main (above)"
    conflicts=$(git diff --name-only --diff-filter=U)
    if grep -qvxE 'CHANGELOG\.md|api/openapi\.baseline\.yaml' <<< "$conflicts"; then
      fail "merging $branch into main conflicts beyond CHANGELOG.md -- resolve it on main, git commit, then git switch $branch"
    fi
    if grep -qx CHANGELOG.md <<< "$conflicts"; then
      theirs=$(mktemp)
      git show "$branch:CHANGELOG.md" > "$theirs"
      git checkout --quiet --ours CHANGELOG.md
      tool/changelog.sh take "$1" "$theirs"
      rm -f "$theirs"
    fi
    if grep -qx api/openapi.baseline.yaml <<< "$conflicts"; then
      git checkout --quiet --ours api/openapi.baseline.yaml
    fi
    git add CHANGELOG.md api/openapi.baseline.yaml
    git commit --quiet --no-edit
  fi
  git switch --quiet "$branch"
}

# The version main works towards: its highest dev tag, empty if it has none.
main_version() {
  git tag --merged main --list 'v*-dev' |
    sed -nE 's/^v([0-9]+)\.([0-9]+)\.([0-9]+)-dev$/\1 \2 \3/p' |
    sort -n -k1,1 -k2,2 -k3,3 | tail -n 1 | tr ' ' .
}
# Whether the version $1 orders below the version $2.
below() {
  [[ "$1" != "$2" && "$(printf '%s\n' "$1" "$2" | sort -t . -k1,1n -k2,2n -k3,3n | head -n 1)" == "$1" ]]
}

# The highest candidate tag of a version, empty if there is none.
last_candidate() {
  git tag --list "v$1-rc.*" | sed -nE 's/^v.*-rc\.([0-9]+)$/\1 &/p' | sort -n | tail -n 1 | cut -d ' ' -f 2
}

case "${1:-}" in
  candidate)
    version="${2:-}"
    [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || usage
    year=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    patch=${BASH_REMATCH[3]}
    branch=release/$version
    clean
    fetch_tags
    has_branch "$branch" && fail "$branch exists already"
    has_tag "v$version" && fail "v$version is released already"
    current=$(main_version)
    [[ -n "$current" ]] || fail "main has no dev tag -- git tag v<version>-dev on main first"
    if ! below "$version" "$current"; then
      start=main
      next=$year.$((minor + 1)).0
      has_tag "v$next-dev" && fail "v$next-dev exists already"
    else
      ((patch > 0)) ||
        fail "$version is below $current, which main works towards: below it only a fix of a release, a patch number, starts a branch"
      start=v$year.$minor.$((patch - 1))
      has_tag "$start" || fail "a fix starts from the release before it, and there is no $start"
    fi

    git switch --quiet -c "$branch" "$start"
    tool/changelog.sh candidate "$version"
    baseline
    git add CHANGELOG.md api/openapi.baseline.yaml
    git commit --quiet -m "chore: Release candidate $version"
    # From here on the branch works towards the version: a build before the first
    # candidate tag carries it already.
    push=("$branch")
    if ! has_tag "v$version-dev"; then
      git tag "v$version-dev"
      push+=("v$version-dev")
    fi

    if [[ "$start" == main ]]; then
      # main takes the start of the branch in at once: Unreleased there is the
      # candidate's now. Its dev tag for the version after sits on the merge, which
      # the release branch does not contain.
      merge_into_main "$version"
      git tag "v$next-dev" main
      push=(main "${push[@]}" "v$next-dev")
      cat << EOF
$branch starts the release candidate $version, from main; main goes on towards $next
(a later year is a newer dev tag on main: git tag v<year>.1.0-dev).
EOF
    else
      cat << EOF
$branch starts the fix $version, from $start. The fixes go into it as fix/… branches,
each with its entry in the section "$version — Release candidate" of CHANGELOG.md.
EOF
    fi
    cat << EOF

  git push origin ${push[*]}

Then, once CI passed for $branch: tool/release.sh rc
EOF
    ;;

  rc)
    version=$(branch_version)
    clean
    fetch_tags
    has_tag "v$version" &&
      fail "$version is released already -- a further fix is the next patch (tool/release.sh candidate <version>)"
    here=$(git tag --points-at HEAD --list "v$version-rc.*")
    [[ -z "$here" ]] || fail "this commit is the candidate $here already"
    last=$(last_candidate "$version")
    n=$((${last:+${last##*.}} + 1))
    tag=v$version-rc.$n
    # A candidate that says nothing would publish an empty pre-release.
    tool/changelog.sh notes "$version-rc.$n" > /dev/null
    git tag "$tag"
    merge_into_main "$version"
    cat << EOF
$tag is the commit checked out, and main has taken the branch in. Push the tag once CI
passed for its commit -- the tag starts the release workflow:

  git push origin main release/$version
  git push origin $tag
EOF
    ;;

  final)
    version=$(branch_version)
    clean
    fetch_tags
    has_tag "v$version" && fail "v$version is released already"
    last=$(last_candidate "$version")
    [[ -n "$last" ]] || fail "no candidate of $version yet: tool/release.sh rc first"
    # The release is the last candidate as it was tested, and its changelog.
    [[ "$(git rev-parse "$last^{commit}")" == "$(git rev-parse HEAD)" ]] ||
      fail "there are commits since $last -- tag a candidate of them first (tool/release.sh rc)"
    tool/changelog.sh release "$version"
    baseline
    git add CHANGELOG.md api/openapi.baseline.yaml
    git commit --quiet -m "chore: Release $version"
    merge_into_main "$version"
    cat << EOF
The release $version is committed on release/$version, and main has taken it in. Push
both, and once CI passed for the release's commit, tag it -- the tag starts the
release workflow:

  git push origin main release/$version
  git tag v$version release/$version && git push origin v$version
EOF
    ;;

  *)
    usage
    ;;
esac
