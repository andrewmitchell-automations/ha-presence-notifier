#!/usr/bin/env bash
# Cut a release: bump version, commit, tag, push, and create a GitHub Release.
# Usage: ./release.sh patch|minor|major

set -euo pipefail

PART="${1:?usage: ./release.sh patch|minor|major}"

case "$PART" in
    patch|minor|major) ;;
    *) echo "release.sh: PART must be patch, minor, or major (got: $PART)" >&2; exit 1 ;;
esac

branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" != "main" ]; then
    echo "release.sh: must be on main (currently on $branch)" >&2
    exit 1
fi

git fetch origin main --quiet
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    echo "release.sh: local main is not in sync with origin/main; pull or push first" >&2
    exit 1
fi

# bump-my-version handles the dirty-tree check, the plugin.json edit, the commit, and the tag.
uvx bump-my-version bump "$PART"

git push --follow-tags

TAG=$(git describe --tags --abbrev=0)
gh release create "$TAG" --title "$TAG" --generate-notes

echo "Released $TAG"
