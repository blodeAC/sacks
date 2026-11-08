#!/bin/sh
# push.sh - release what is installed in the game: copy it into this repo, commit, tag, push, and publish a GitHub
# release so instawow sees an update.
#   ./push.sh "what changed"            release
#   ./push.sh --minor "what changed"    minor bump   (0.0.2 -> 0.1.0)
#   ./push.sh --major "what changed"    major bump   (0.1.0 -> 1.0.0)
# The version is the one in the installed .toc when that is newer than the last release (the builds you tested keep
# their number), else the last release plus one. The message is used for the commit and the release notes.
# Needs git and gh (logged in).

ADDON_FOLDER=sacks   # the folder name inside the release zip, which must match the .toc name
INSTALLED="$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/$ADDON_FOLDER"

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

toc="./$ADDON_FOLDER.toc"
tocVersion() { sed -n -E 's/^## Version:[[:space:]]*([0-9.]+).*/\1/p' "$1" 2>/dev/null | head -n 1; }

# the installed copy is what you tested: bring it in (this script and the repo's own files stay as they are)
if [ -f "$INSTALLED/$ADDON_FOLDER.toc" ]; then
    installed=$(tocVersion "$INSTALLED/$ADDON_FOLDER.toc")
    # the repo becomes exactly the installed folder; this script and dotfiles (.git, .gitignore) are left alone
    find . -mindepth 1 -maxdepth 1 ! -name '.*' ! -name push.sh -exec rm -rf {} + || exit 1
    find "$INSTALLED" -mindepth 1 -maxdepth 1 ! -name '.*' ! -name push.sh -exec cp -a {} ./ \; || exit 1
    echo "Copied the installed $ADDON_FOLDER ($installed) into the repo."
else
    echo "No installed $ADDON_FOLDER at $INSTALLED, releasing the repo as it is."
fi

# the last release, from the newest v* tag
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

# the version: the .toc's when it is newer than the last release and no bigger bump was asked for, else a bump
current=$(tocVersion "$toc")
newest=$(printf '%s\n%s\n' "${last#v}" "$current" | sort -V | tail -n 1)
if [ "$bump" = patch ] && [ -n "$current" ] && [ "$current" != "${last#v}" ] && [ "$newest" = "$current" ]; then
    version=$current
else
    IFS=. read -r major minor patch <<EOT
${last#v}
EOT
    case "$bump" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        *)     patch=$((patch + 1)) ;;
    esac
    version="$major.$minor.$patch"
fi
tag="v$version"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "$tag already exists, stopping."
    exit 1
fi

echo "Releasing $tag (was $last):"
git status --short
echo

# write the version into the .toc (here and in the installed copy, so both say what was released)
if [ ! -f "$toc" ]; then
    echo "No $toc found, stopping."
    exit 1
fi
for file in "$toc" "$INSTALLED/$ADDON_FOLDER.toc"; do
    [ -f "$file" ] || continue
    if grep -q '^## Version:' "$file"; then
        sed -i -E "s/^## Version:.*/## Version: $version/" "$file"
    else
        echo "## Version: $version" >> "$file"
    fi
done

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
