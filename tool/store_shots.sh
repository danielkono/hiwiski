#!/usr/bin/env bash
# The store pictures' golden tests (app/test/store), run as CI runs them: on Linux,
# x86-64, with the Flutter version from app/.fvmrc. On a Mac the test skips its
# goldens, because fonts render a little differently there.
#
#   tool/store_shots.sh            compare the pictures with their goldens
#   tool/store_shots.sh --update   draw the goldens anew (after a change that shows)
#
# Needs Docker that runs linux/amd64 images (colima: with Rosetta or QEMU). The app is
# copied into the container, so nothing of the Linux build ends up in the checkout;
# only the goldens (with --update) and the differences of a failed run come back to
# app/test/store/.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
flutter="$(sed -n 's/.*"flutter": *"\([^"]*\)".*/\1/p' "$root/app/.fvmrc")"
image="hiwiski-store-shots:$flutter"

update=""
case "${1:-}" in
  "") ;;
  --update) update="--update-goldens" ;;
  *) echo "usage: $0 [--update]" >&2; exit 2 ;;
esac

docker build --quiet --platform linux/amd64 --build-arg "FLUTTER=$flutter" \
  -t "$image" "$root/tool/store_shots" >/dev/null

store="$root/app/test/store"
rm -rf "$store/failures"
mkdir -p "$store/goldens" "$store/failures"

# The app and the contract the client is generated from, without what a build left.
# Without the Mac's metadata: its tar adds a "._" file for every file with extended
# attributes, and the code generators then trip over "._app_de.arb".
COPYFILE_DISABLE=1 tar -C "$root" -c --no-xattrs \
  --exclude='app/build' --exclude='app/.dart_tool' --exclude='app/.fvm' \
  --exclude='app/lib/core/api/generated' --exclude='app/lib/core/l10n/generated' \
  --exclude='*.g.dart' --exclude='*.freezed.dart' \
  --exclude='app/test/store/failures' \
  app api/openapi.bundled.yaml \
| docker run --rm -i --platform linux/amd64 \
    -v hiwiski-store-shots-pub:/root/.pub-cache \
    -v "$store/goldens:/out/goldens" \
    -v "$store/failures:/out/failures" \
    "$image" bash -euo pipefail -c "
      mkdir /work && tar -x -C /work
      cd /work/app
      flutter pub get >/dev/null
      dart run swagger_parser >/dev/null
      dart run build_runner build --delete-conflicting-outputs >/dev/null
      status=0
      flutter test test/store $update || status=\$?
      if [ -n '$update' ]; then
        rm -rf /out/goldens/* && cp -r test/store/goldens/. /out/goldens/
      fi
      if [ -d test/store/failures ]; then cp -r test/store/failures/. /out/failures/; fi
      exit \$status
    "

rmdir "$store/failures" 2>/dev/null || echo "Differences: $store/failures" >&2
