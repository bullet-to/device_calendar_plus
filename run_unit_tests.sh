#!/bin/bash
# Runs `flutter test` in every package with a test/ dir, so a new package is
# picked up without editing a list. Keeps going after a failure so one run
# reports every failing package, then exits non-zero if any failed.
# CI's "Unit tests" step runs this script too.

cd "$(dirname "$0")" || exit 1

# Collapsible log sections on GitHub Actions, plain headers locally.
group() {
  if [ -n "$GITHUB_ACTIONS" ]; then echo "::group::$1"; else echo "== $1"; fi
}
endgroup() {
  if [ -n "$GITHUB_ACTIONS" ]; then echo "::endgroup::"; fi
}

status=0
for test_dir in packages/*/test; do
  package=$(dirname "$test_dir")
  group "$package"
  (cd "$package" && flutter test) || status=1
  endgroup
done
exit $status
