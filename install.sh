#!/bin/sh
# Install `ayg`, the command an operator's laptop runs for an Ayg robot.
#
# It takes the `ayg` built for this machine from the releases and puts it in ~/.local/bin.
# The releases are private: the download goes through GitHub's own CLI and the account you
# are logged in with there (`gh auth login`), so this script gives nothing to anybody who was
# not given access.
#
#   --release <n>   the `ayg` of release n (default: of the newest promoted release)
#   --candidate     of the newest candidate, if newer: for the lab's own laptops
#
# Run again to replace the `ayg` that is installed with a newer one.
set -eu

repo="${AYG_DIST_REPO:-Cyber-Fusion/ayg-dist}"
bin="${AYG_INSTALL_DIR:-$HOME/.local/bin}"
tag=""
candidate=false
while [ $# -gt 0 ]; do
    case "$1" in
        --release)
            [ $# -ge 2 ] || { echo "install.sh: --release takes a number" >&2; exit 2; }
            tag="ayg-$2"
            shift 2
            ;;
        --candidate)
            candidate=true
            shift
            ;;
        *)
            echo "install.sh: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

case "$(uname -s) $(uname -m)" in
    "Linux x86_64") file=ayg-linux-x86_64 ;;
    "Linux aarch64" | "Linux arm64") file=ayg-linux-aarch64 ;;
    "Darwin arm64") file=ayg-macos-arm64 ;;
    *)
        echo "ayg is built for Linux (x86_64 and arm64) and for macOS on Apple Silicon;" >&2
        echo "this machine is $(uname -s) $(uname -m)." >&2
        exit 1
        ;;
esac

if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub's CLI (gh) is needed: the releases are private and it is how this machine" >&2
    echo "reaches them. Install it (https://cli.github.com), then: gh auth login" >&2
    exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    echo "Log in first, with the account that was given access:  gh auth login" >&2
    exit 1
fi

# A release is tagged ayg-<n>; a pre-release is a candidate.
newest() {
    gh release list --repo "$repo" --limit 100 --json tagName,isDraft,isPrerelease \
        --jq "[.[] | select(.isDraft | not) | select($1) | .tagName
               | select(test(\"^ayg-[0-9]+\$\"))]
              | sort_by(ltrimstr(\"ayg-\") | tonumber) | last // empty"
}
if [ -z "$tag" ]; then
    if $candidate; then
        tag=$(newest "true")
    else
        tag=$(newest ".isPrerelease | not")
    fi
    if [ -z "$tag" ]; then
        if $candidate; then
            echo "$repo holds no release yet." >&2
        else
            echo "$repo holds no promoted release yet (a candidate is for the lab: --candidate)." >&2
        fi
        exit 1
    fi
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM
echo "• fetching $file of ${tag} from $repo …"
if ! gh release download "$tag" --repo "$repo" --dir "$tmp" --pattern "$file" --pattern SHA256SUMS; then
    echo "$file of ${tag} could not be fetched from $repo: is there such a release, and was" >&2
    echo "the account you are logged in with given access? Nothing was installed." >&2
    exit 1
fi

want=$(awk -v f="$file" '$2 == f || $2 == "*" f { print $1 }' "$tmp/SHA256SUMS")
if command -v sha256sum >/dev/null 2>&1; then
    have=$(sha256sum "$tmp/$file" | cut -d' ' -f1)
else
    have=$(shasum -a 256 "$tmp/$file" | cut -d' ' -f1)
fi
if [ -z "$want" ] || [ "$want" != "$have" ]; then
    echo "What was fetched is not the file the release lists: nothing was installed." >&2
    exit 1
fi

# Put beside its place first, then moved into it: an `ayg` that is running is never half
# replaced.
mkdir -p "$bin"
cp "$tmp/$file" "$bin/.ayg.new"
chmod 755 "$bin/.ayg.new"
mv -f "$bin/.ayg.new" "$bin/ayg"
echo "✓ $("$bin/ayg" --version) (${tag}) is at $bin/ayg"

case ":$PATH:" in
    *":$bin:"*) ;;
    *)
        echo "  $bin is not on your PATH: add it (in ~/.profile or ~/.zshrc):"
        echo "    export PATH=\"$bin:\$PATH\""
        ;;
esac
echo "  Next: ayg update <user@robot> installs the newest release on a robot."
