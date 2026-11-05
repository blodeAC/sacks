#!/bin/sh
# push.sh - commit, bump the version, tag, push, and publish a GitHub release so instawow sees an update.
#   ./push.sh "what changed"            patch bump   (0.0.1 -> 0.0.2)
#   ./push.sh --minor "what changed"    minor bump   (0.0.2 -> 0.1.0)
#   ./push.sh --major "what changed"    major bump   (0.1.0 -> 1.0.0)
# The message is used for the commit and the release notes. Needs git and gh (logged in).

ADDON_FOLDER=sacks   # the folder name inside the release zip, which must match the .toc name

cd "$(dirname "$0")" || exit 1

bump=patch
message=
for arg in "$@"; do
    case "$arg" in
        --minor) bump=minor ;;
        --major) bump=major ;;
        *) message=$arg ;;
    esac
done
[ -z "$message" ] && message="update $(date '+%Y-%m-%d %H:%M')"

# next version, from the newest v* tag
git fetch --tags --quiet
last=$(git tag --list 'v*' --sort=-v:refname | head -n 1)
[ -z "$last" ] && last=v0.0.0

# release when files changed OR commits exist that no release has picked up yet
if [ -z "$(git status --porcelain)" ]; then
    if [ "$last" = v0.0.0 ] || [ "$(git rev-list --count "$last"..HEAD)" = 0 ]; then
        echo "Nothing changed since $last, nothing to release."
        exit 0
    fi
    echo "No file changes, but $(git rev-list --count "$last"..HEAD) commit(s) since $last are not released yet."
fi
IFS=. read -r major minor patch <<EOT
${last#v}
EOT
case "$bump" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    *)     patch=$((patch + 1)) ;;
esac
version="$major.$minor.$patch"
tag="v$version"

echo "Releasing $tag (was $last):"
git status --short
echo

# write the version into the .toc
toc=$(ls ./*.toc 2>/dev/null | head -n 1)
if [ -z "$toc" ]; then
    echo "No .toc file found, stopping."
    exit 1
fi
if grep -q '^## Version:' "$toc"; then
    sed -i -E "s/^## Version:.*/## Version: $version/" "$toc"
else
    echo "## Version: $version" >> "$toc"
fi

git add -A || exit 1
git commit -m "$message ($tag)" || exit 1
git tag -a "$tag" -m "$message" || exit 1
git push --follow-tags || exit 1

# the release zip holds exactly what is committed, inside a folder named like the addon
zip="$(mktemp -d)/$ADDON_FOLDER-$tag.zip"
git archive --format=zip --prefix="$ADDON_FOLDER/" -o "$zip" "$tag" || exit 1
gh release create "$tag" "$zip" --title "$tag" --notes "$message" || exit 1
rm -f "$zip"
echo "Done: $tag. Run 'instawow update' to pick it up."
