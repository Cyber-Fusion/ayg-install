# ayg-install

Installs `ayg`, the command an operator's laptop runs for an Ayg robot:

    curl -fsSL https://raw.githubusercontent.com/Cyber-Fusion/ayg-install/main/install.sh | sh

It needs [GitHub's CLI](https://cli.github.com), logged in (`gh auth login`) with an account
that was given access to the releases: the script downloads nothing for anybody else.

Linux on x86_64 or arm64 (Ubuntu 22.04 or newer), macOS on Apple Silicon.

This repository is the script's temporary home.
