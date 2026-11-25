#!/bin/sh
# Install `ayg`, the command an operator's laptop runs for an Ayg robot.
#
# It takes the `ayg` built for this machine from the releases and puts it in ~/.local/bin.
# The releases are private: the download goes through GitHub's own CLI and the account you
# are logged in with there (`gh auth login`), so this script gives nothing to anybody who was
# not given access.
#
#   --release <n>   the `ayg` of release n (default: of the newest promoted release)
#   --candidate     of a candidate, a release nobody promoted yet: the newest of either
#                   kind, or with --release the one named. For the lab's own laptops
#
# Run again to replace the `ayg` that is installed with a newer one.
set -eu

# All of it in one function, called on the last line: a download that was cut short runs
# nothing.
main() {
    # A `cd` goes where it is told, by no search path of the caller's.
    unset CDPATH
    # The distribution repo, on GitHub itself whatever other host this machine's gh knows.
    # No setting names another: whose releases a laptop takes is not left to its environment.
    repo="github.com/Cyber-Fusion/ayg-dist"
    bin="${AYG_INSTALL_DIR:-$HOME/.local/bin}"
    tag=""
    candidate=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --release)
                [ $# -ge 2 ] || { echo "install.sh: --release takes a number" >&2; exit 2; }
                case "$2" in
                    "" | *[!0-9]*) echo "install.sh: --release takes a number" >&2; exit 2 ;;
                esac
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

    # Where an `ayg` lies says what it is. One under an Ayg checkout is that checkout's
    # (built there, by `ayg launcher build`), one beside what cargo builds is a build, one in
    # a release's directory is the release's: each runs a robot's command for the tree it is
    # part of. An installed `ayg` is a file of its own, and is put nowhere else.
    part_of() {
        echo "$bin is $1:" >&2
        echo "an ayg put there would be taken for a part of it, not for an installed one." >&2
        echo "Choose another directory (the default is ~/.local/bin). Nothing was installed." >&2
        exit 1
    }
    # One destination, found once, checked and then written to: by its whole path from the
    # root, the part of it that is there as it resolves (links followed), and below that
    # what is yet to be made, in plain names (a `..` there would lead out of what was
    # checked).
    case "$bin" in
        /*) dest="$bin" ;;
        *) dest="$(pwd -P)/$bin" ;;
    esac
    at="$dest"
    rest=""
    while [ ! -d "$at" ]; do
        up=$(dirname "$at")
        [ "$up" != "$at" ] || break
        rest="/$(basename "$at")$rest"
        at="$up"
    done
    case "$rest/" in
        */../* | */./*)
            echo "$bin: write the directory without \`.\` or \`..\` in what is yet to be made." >&2
            echo "Nothing was installed." >&2
            exit 1
            ;;
    esac
    # `cd -P`: each link followed where it stands, so that a `..` after one is the directory
    # above what the link names, as the system reads the path, not above the link.
    at=$(cd -P "$at" 2>/dev/null && pwd -P) || {
        echo "$bin cannot be reached. Nothing was installed." >&2
        exit 1
    }
    dest="${at%/}$rest"
    [ -n "$dest" ] || dest=/
    if [ -e "$dest/.cargo-lock" ] || [ -d "$dest/.fingerprint" ]; then
        part_of "a directory cargo builds into"
    fi
    # A release's, as `ayg` itself tells one: a numbered directory in one named `releases`,
    # or a directory that holds a release's manifest.
    # (A number may be written with a sign before it, and is one to `ayg` then too.)
    numbered=$(basename "$dest")
    numbered=${numbered#+}
    case "$numbered" in
        "" | *[!0-9]*) ;;
        *) [ "$(basename "$(dirname "$dest")")" != releases ] || part_of "a release's directory" ;;
    esac
    if [ -e "$dest/release.json" ]; then
        part_of "a release's directory"
    fi
    # And what is at the file's own place must be a file to replace, or nothing: a directory
    # of that name (a checkout called Ayg, where names differ only by case) would take the
    # new file inside itself.
    if [ -d "$dest/ayg" ]; then
        echo "$dest/ayg is a directory: an ayg cannot be put in its place." >&2
        echo "Choose another directory (the default is ~/.local/bin). Nothing was installed." >&2
        exit 1
    fi
    while :; do
        [ ! -f "$at/ros/Makefile" ] || part_of "inside the Ayg checkout at $at"
        [ "$at" != "/" ] || break
        at=$(dirname "$at")
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
    # What gh says when it is asked for a release is the answer: a check of the login ahead
    # of that can fail over an account this has nothing to do with.
    no_access() {
        echo "$repo could not be read. Log in with the account that was given access" >&2
        echo "(gh auth login), or ask for that access. Nothing was installed." >&2
        exit 1
    }

    # A release is tagged ayg-<n>; a pre-release is a candidate.
    newest() {
        gh release list --repo "$repo" --limit 10000 --json tagName,isDraft,isPrerelease \
            --jq "[.[] | select(.isDraft | not) | select($1) | .tagName
                   | select(test(\"^ayg-[0-9]+\$\"))]
                  | sort_by(ltrimstr(\"ayg-\") | tonumber) | last // empty"
    }
    if [ -z "$tag" ]; then
        if $candidate; then
            tag=$(newest "true") || no_access
        else
            tag=$(newest ".isPrerelease | not") || no_access
        fi
        if [ -z "$tag" ]; then
            if $candidate; then
                echo "$repo holds no release yet." >&2
            else
                echo "$repo holds no promoted release yet (a candidate is for the lab: --candidate)." >&2
            fi
            exit 1
        fi
    else
        # A release that is named is asked what it is: a candidate is taken only when one
        # is asked for, as `ayg update` takes it.
        kind=$(gh release view "$tag" --repo "$repo" --json isDraft,isPrerelease \
            --jq 'if .isDraft then "draft" elif .isPrerelease then "candidate" else "release" end') || {
            echo "${tag} could not be read from $repo: is there such a release, and was the" >&2
            echo "account you are logged in with given access? Nothing was installed." >&2
            exit 1
        }
        case "$kind" in
            release) ;;
            candidate)
                if ! $candidate; then
                    echo "${tag} is a candidate, not promoted yet: it is taken only with" >&2
                    echo "--candidate, for the lab's own laptops. Nothing was installed." >&2
                    exit 1
                fi
                ;;
            *)
                echo "$repo holds no ${tag}. Nothing was installed." >&2
                exit 1
                ;;
        esac
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

    # Put beside its place under a name of its own, seen to start on this machine, and only
    # then moved into its place: the `ayg` that is there is never half replaced, and never
    # replaced by one that does not run here.
    mkdir -p "$dest"
    new=$(mktemp "$dest/.ayg.XXXXXX")
    trap 'rm -rf "$tmp" "$new"' EXIT
    cp "$tmp/$file" "$new"
    chmod 755 "$new"
    if ! version=$("$new" --version 2>&1); then
        echo "The ayg that was fetched does not start on this machine:" >&2
        echo "  $version" >&2
        echo "Nothing was installed: what was at $dest/ayg is as it was." >&2
        exit 1
    fi
    mv -f "$new" "$dest/ayg"
    echo "✓ $version (${tag}) is at $dest/ayg"

    # A plain `ayg` must be this one, from any directory and in a terminal that ran another
    # before: another on PATH (a checkout's, linked into ~/.local/bin by its build) runs a
    # robot's command on this machine. So PATH is read entry by entry, not asked of a shell:
    # this one counts where an entry written from the root reaches it (one written from
    # where this was run names another directory from anywhere else), and another `ayg`
    # anywhere on PATH is said, before this one or after it (a terminal remembers the one
    # it ran). What is suggested is the whole path, first.
    ours=""
    other=""
    old_ifs=$IFS
    IFS=:
    set -f
    for entry in $PATH; do
        [ -n "$entry" ] || entry=.
        if [ -f "$entry/ayg" ] && [ -x "$entry/ayg" ]; then
            if [ "$entry/ayg" -ef "$dest/ayg" ]; then
                case "$entry" in
                    /*) ours=yes ;;
                esac
            elif [ -z "$other" ]; then
                other="$entry/ayg"
            fi
        fi
    done
    set +f
    IFS=$old_ifs
    if [ -n "$other" ]; then
        echo "  NOTE: another ayg is on your PATH: $other"
        echo "  A plain \`ayg\` must be the one just installed: a terminal runs the first on its"
        echo "  PATH, and remembers one it ran before. Put this directory first, in this terminal"
        echo "  and in ~/.profile or ~/.zshrc, or take the other one away:"
        echo "    export PATH=\"$dest:\$PATH\""
    elif [ -z "$ours" ]; then
        echo "  $dest is not on your PATH: add it (in ~/.profile or ~/.zshrc):"
        echo "    export PATH=\"$dest:\$PATH\""
    fi
    echo "  Next: \`ayg docs\` is the guide: aiming ayg at your robot, updating it, going back."
}

# In braces: a download cut anywhere in this line, too, runs nothing.
{ main "$@"; }
