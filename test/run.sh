#!/bin/bash
# Scenario tests for bin/kitchen against stub herdr, codex, and gh.
# Usage: test/run.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export PATH="$ROOT/test/stubs:$PATH" HERDR_ENV=1 KITCHEN_DATA="$T/data" STUB_LOG="$T/log"
K="$ROOT/bin/kitchen"
fails=0

ok()   { echo "ok    $1"; }
fail() { echo "FAIL  $1"; fails=$((fails+1)); }
check() { local what=$1; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else fail "$what"; fi; }
has()  { grep -qF -- "$2" <<<"$1"; }
calls() { grep -cF -- "$1" "$STUB_LOG" || true; }

# A repository with an origin, the way kitchen expects it.
git init -q --bare "$T/origin.git"
git init -q -b main "$T/repo"
cd "$T/repo"
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git remote add origin "$T/origin.git"; git push -q -u origin main; git remote set-head origin main
W="$T/data/worktrees/repo--w1"

echo "# worker"
out=$("$K" worker w1 feat/x 2>&1)
check "prints the worker line"            has "$out" "worker=w1"
check "creates the worktree on the branch" test "$(git -C "$W" branch --show-current)" = feat/x
check "writes the record"                  grep -q '^BASE=origin/main$' "$T/data/state/w1"
check "links the shared notes"             test -L "$W/.kitchen/notes.md"
check "keeps .kitchen out of git"          grep -qx '.kitchen/' "$T/repo/.git/info/exclude"
check "starts claude without prompts"      has "$(cat "$STUB_LOG")" "[--dangerously-skip-permissions]"
check "refuses a duplicate name"           bash -c "! '$K' worker w1 feat/y"

echo "# worker rollback"
out=$(STUB_FAIL_WORKSPACE=1 "$K" worker w2 feat/z 2>&1)
check "reports the failure"                has "$out" "nothing was left behind"
check "leaves no worktree"                 test ! -e "$T/data/worktrees/repo--w2"
check "leaves no branch"                   bash -c "! git -C '$T/repo' rev-parse --verify -q feat/z"

echo "# check"
out=$("$K" check w1 2>&1)
check "prints the verdict"                 has "$out" "[P1] Off-by-one"
check "prints the card"                    has "$out" "TESTS: 2/2"
check "keeps the transcript out"           bash -c "! grep -q noise '$W/.kitchen/review.txt'"
check "saves the transcript"               grep -q noise "$W/.kitchen/review.log"
check "opens the pane once"                test "$(calls '[pane] [split]')" = 1
"$K" check w1 >/dev/null 2>&1
check "does not repeat for the same commit" test "$(calls 'codex [review]')" = 1
git -C "$W" -c user.name=t -c user.email=t@t commit -q --allow-empty -m fix
"$K" check w1 >/dev/null 2>&1
check "runs again for a new commit"        test "$(calls 'codex [review]')" = 2
check "reuses the pane"                    test "$(calls '[pane] [split]')" = 1
git -C "$W" -c user.name=t -c user.email=t@t commit -q --allow-empty -m fix2
out=$(STUB_FAIL_REVIEW=1 "$K" check w1 2>&1)
check "reports a failed review as a tool error" has "$out" "command FAILED (exit 3)"

echo "# done"
out=$("$K" done w1 2>&1)
check "refuses without a merged PR"        has "$out" "not merged"
check "keeps the worktree then"            test -d "$W"
out=$(STUB_PR_STATE=MERGED "$K" done w1 2>&1)
check "removes a merged worker"            has "$out" "merged branch feat/x"
check "removes the worktree"               test ! -e "$W"
check "removes the branch"                 bash -c "! git -C '$T/repo' rev-parse --verify -q feat/x"
check "removes the record"                 test ! -e "$T/data/state/w1"

echo "# done --force"
"$K" worker w3 feat/k >/dev/null 2>&1
out=$("$K" done w3 --force 2>&1)
check "removes the worker"                 test ! -e "$T/data/worktrees/repo--w3"
check "keeps the unmerged branch"          git -C "$T/repo" rev-parse --verify -q feat/k

echo "# records written by older versions"
"$K" worker w4 feat/old >/dev/null 2>&1
printf 'RWS=w8\nRPANE=w8:p1\nQWS=w9\n' >> "$T/data/state/w4"
STUB_PR_STATE=MERGED "$K" done w4 >/dev/null 2>&1
check "closes the old review workspace"    has "$(cat "$STUB_LOG")" "[workspace] [close] [w8]"
check "closes the old tester workspace"    has "$(cat "$STUB_LOG")" "[workspace] [close] [w9]"

echo
if [ "$fails" = 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
