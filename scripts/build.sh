#!/usr/bin/env bash
# Fetch upstream rclone-extra at the pinned commit, apply the direct-link patch
# and cross-compile. Same ldflags as the released binary, so `rclone version`
# reports the same string.
#
#   ./scripts/build.sh                    # windows/amd64 (default)
#   GOOS=linux GOARCH=amd64 ./scripts/build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

UPSTREAM="${UPSTREAM:-https://github.com/gulp79/rclone-extra.git}"
COMMIT="${COMMIT:-066443b420e185d8795f832d29055174a68b7694}"
VERSION="${VERSION:-v1.75.2-extra-11-g066443b4-directlink}"
GOOS="${GOOS:-windows}"
GOARCH="${GOARCH:-amd64}"

work="${WORKDIR:-$root/_build}"
src="$work/rclone-extra"
out="$root/out/rclone-$VERSION-$GOOS-$GOARCH"
[ "$GOOS" = "windows" ] && out="$out.exe"

patch="$root/patches/rclone-extra.diff"
[ -f "$patch" ] || { echo "missing patch: $patch" >&2; exit 1; }

mkdir -p "$work" "$root/out"

if [ "${REUSE_SRC:-0}" = "1" ] && [ -d "$src/.git" ]; then
  echo "== reusing $src"
else
  rm -rf "$src"
  mkdir -p "$src"
  echo "== fetching $UPSTREAM @ $COMMIT"
  git -C "$src" init -q
  git -C "$src" remote add origin "$UPSTREAM"
  git -C "$src" fetch --depth 1 origin "$COMMIT"
  git -C "$src" checkout -q FETCH_HEAD
fi

head="$(git -C "$src" rev-parse HEAD)"
[ "$head" = "$COMMIT" ] || { echo "source tree at $head, expected $COMMIT" >&2; exit 1; }

git -C "$src" apply "$patch"
echo "== patch applied"

export CGO_ENABLED=0 GOOS GOARCH
echo "== go build $GOOS/$GOARCH -> $out"
( cd "$src" && go build -trimpath \
    -ldflags "-s -w -X github.com/rclone/rclone/fs.Version=$VERSION" \
    -o "$out" . )

echo
echo "built  : $out"
echo "size   : $(wc -c < "$out") B"
echo "sha256 : $(sha256sum "$out" | cut -d' ' -f1)"
"$out" version 2>/dev/null | head -1 || true
