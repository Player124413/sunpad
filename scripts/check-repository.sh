#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

git diff --check

for script in scripts/*.sh tests/*.sh apple/macos/SunPad; do
  bash -n "$script"
done

python3 -c 'import ast,pathlib; [ast.parse(p.read_text(), filename=str(p)) for p in pathlib.Path("scripts").glob("*.py")]'
python3 -c 'import json,pathlib; [json.loads(p.read_text()) for p in pathlib.Path("apple/ios/Assets.xcassets").rglob("*.json")]'
plutil -lint apple/ios/Info.plist apple/macos/Info.plist
./scripts/check-markdown-links.py

./tests/test-input-pipe-encoder.sh
./tests/test-diagnostics.sh

prohibited=$(git ls-files | grep -E '(^|/)(ref|DerivedData|Provisioned|build[^/]*)/|\.(iso|gcm|rvz|wia|wbfs|gcz|dylib|ipa|xcarchive|mobileprovision|p12|pem|key|gci|sav|raw)$' || true)
if [[ -n "$prohibited" ]]; then
  echo "prohibited tracked material:" >&2
  echo "$prohibited" >&2
  exit 1
fi

if git grep -n -I -E 'BEGIN [A-Z ]*PRIVATE KEY|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}' -- .; then
  echo "possible credential material found" >&2
  exit 1
fi

if git grep -n -I '/Users/' -- . ':!scripts/check-repository.sh'; then
  echo "personal absolute path found" >&2
  exit 1
fi

test -f LICENSE
test -f THIRD_PARTY_NOTICES.md
echo "Repository checks passed"
