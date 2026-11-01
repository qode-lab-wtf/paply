#!/bin/bash
# Bringt ein fertiges Release ins öffentliche Download-Repository und gibt es frei (siehe docs/RELEASE.md).
set -euo pipefail

CODE=qode-lab-wtf/paply
DOWNLOADS=qode-lab-wtf/paply-downloads
COMMAND=${1:-}
VERSION=${2:-}
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Aufruf: release-downloads.sh spiegeln|freigeben <Version>"; exit 1; }
TAG=v$VERSION

case $COMMAND in
  spiegeln)
    DIR=$(mktemp -d)
    trap 'rm -rf "$DIR"' EXIT
    gh release download "$TAG" --repo "$CODE" --dir "$DIR"
    gh release create "$TAG" "$DIR"/* --repo "$DOWNLOADS" --prerelease \
      --title "Paply $VERSION" --notes "Paply $VERSION für Mac und Windows."
    ;;
  freigeben)
    for REPO in "$DOWNLOADS" "$CODE"; do
      gh release edit "$TAG" --repo "$REPO" --prerelease=false --latest
    done
    ;;
  *)
    echo "Aufruf: release-downloads.sh spiegeln|freigeben <Version>"
    exit 1
    ;;
esac
