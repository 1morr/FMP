#!/bin/bash
# Copy app/ (tracked and untracked files, minus gitignored ones) and the
# winpc scripts to winpc:C:\fmp-wt over SSH. No git push involved.
# The old C:\fmp-wt\app is removed first, so the next build starts clean.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
(cd "$repo" && git ls-files -co --exclude-standard app |
  COPYFILE_DISABLE=1 tar -cf "$tmp/app.tar" -T -)
ssh winpc 'New-Item -ItemType Directory -Force C:\fmp-wt | Out-Null; Remove-Item -Recurse -Force C:\fmp-wt\app -EA SilentlyContinue'
scp -q "$tmp/app.tar" "$here/build.ps1" "$here/test.ps1" "$here/shot.ps1" winpc:C:/fmp-wt/
ssh winpc 'cd C:\fmp-wt; tar -xf app.tar; Remove-Item app.tar'
