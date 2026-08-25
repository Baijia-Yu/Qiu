#!/bin/zsh
set -euo pipefail

profile=${1:-qiu-notary}

echo "Apple will prompt for your Apple ID, Team ID, and app-specific password."
xcrun notarytool store-credentials "$profile"
