#!/bin/bash
# Scenario tests for bin/kitchen against stub herdr, codex, gh, xcrun, ssh, and scp.
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
git init -q --bare -b main "$T/origin.git"
git init -q -b main "$T/repo"
cd "$T/repo" || exit 1
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
check "opens the workers workspace"        has "$(cat "$STUB_LOG")" "[--label] [repo workers]"
check "labels the pane"                    has "$(cat "$STUB_LOG")" "[pane] [rename] [w1:p1] [w1]"

echo "# second worker"
"$K" worker w5 feat/five >/dev/null 2>&1
check "shares the workers workspace"       test "$(calls '[workspace] [create]')" = 1
check "gets its own pane"                  grep -q '^PANE=w1:s1$' "$T/data/state/w5"
check "splits the wide pane to the right"  has "$(cat "$STUB_LOG")" "[pane] [split] [w1:p1] [--direction] [right]"
"$K" "done" w5 --force >/dev/null 2>&1
check "closes its pane when done"          has "$(cat "$STUB_LOG")" "[pane] [close] [w1:s1]"

echo "# existing branch"
git -C "$T/repo" branch feat/kept
out=$("$K" worker w6 feat/kept 2>&1)
check "continues an existing branch"       test "$(git -C "$T/data/worktrees/repo--w6" branch --show-current)" = feat/kept
"$K" "done" w6 --force >/dev/null 2>&1

echo "# worker rollback"
out=$(STUB_FAIL_WORKSPACE=1 "$K" worker w2 feat/z 2>&1)
check "reports the failure"                has "$out" "nothing was left behind"
check "leaves no worktree"                 test ! -e "$T/data/worktrees/repo--w2"
check "leaves no branch"                   bash -c "! git -C '$T/repo' rev-parse --verify -q feat/z"
check "releases the lock"                  test ! -e "$T/data/lock"

echo "# check"
out=$("$K" check w1 2>&1)
check "prints the verdict"                 has "$out" "[P1] Off-by-one"
check "prints the card"                    has "$out" "TESTS: 2/2"
check "keeps the transcript out"           bash -c "! grep -q noise '$W/.kitchen/review.txt'"
check "saves the transcript"               grep -q noise "$W/.kitchen/review.log"
check "opens the checks workspace"         has "$(cat "$STUB_LOG")" "[--label] [repo checks]"
check "opens the check pane once"          test "$(calls '[repo checks]')" = 1
"$K" check w1 >/dev/null 2>&1
check "does not repeat for the same commit" test "$(calls 'codex [review]')" = 1
git -C "$W" -c user.name=t -c user.email=t@t commit -q --allow-empty -m fix
"$K" check w1 >/dev/null 2>&1
check "runs again for a new commit"        test "$(calls 'codex [review]')" = 2
check "reuses the check pane"              test "$(calls '[repo checks]')" = 1
git -C "$W" -c user.name=t -c user.email=t@t commit -q --allow-empty -m fix2
out=$(STUB_FAIL_REVIEW=1 "$K" check w1 2>&1)
check "reports a failed review as a tool error" has "$out" "command FAILED (exit 3)"
n=$(calls 'codex [review]')
"$K" check w1 >/dev/null 2>&1
check "reviews again after a failed review" test "$(calls 'codex [review]')" = $((n+1))
git -C "$W" -c user.name=t -c user.email=t@t commit -q --allow-empty -m fix3
out=$(STUB_FAIL_TEST=1 "$K" check w1 2>&1)
check "reports a missing card as a tool error" has "$out" "NO CARD (exit 1)"
n=$(calls 'codex [review]'); t=$(calls 'codex [exec]')
out=$("$K" check w1 2>&1)
check "tests again after a failed test"    test "$(calls 'codex [exec]')" = $((t+1))
check "keeps the review that succeeded"    test "$(calls 'codex [review]')" = "$n"
check "prints both results then"           bash -c 'grep -qF "[P1]" <<<"$1" && grep -qF "TESTS: 2/2" <<<"$1"' _ "$out"

echo "# tail"
mkdir -p "$T/home/.claude/projects/p"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"first"}]}}' \
  '{"type":"user","message":{"content":"x"}}' \
  '{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"t"},{"type":"text","text":"last message"}]}}' \
  > "$T/home/.claude/projects/p/sess1.jsonl"
check "prints the agent's last message"    test "$(HOME="$T/home" "$K" tail w1)" = "last message"

echo "# sim"
sim=$(cd "$W" && "$K" sim 2>&1)
check "creates a simulator for the worktree" grep -q "kitchen-repo--w1 ($sim) (Booted)" "$STUB_LOG.sims"
check "prints the same one again"          test "$(cd "$W" && "$K" sim 2>&1)" = "$sim"
check "creates it only once"               test "$(calls '[simctl] [create]')" = 1
git -C "$W" -c user.name=t -c user.email=t@t commit -q --allow-empty -m again
"$K" check w1 >/dev/null 2>&1
check "shuts it down after a check"        grep -q "($sim) (Shutdown)" "$STUB_LOG.sims"

echo "# done"
out=$("$K" "done" w1 2>&1)
check "refuses without a merged PR"        has "$out" "not merged"
check "keeps the worktree then"            test -d "$W"
out=$(STUB_PR_STATE=MERGED "$K" "done" w1 2>&1)
check "removes a merged worker"            has "$out" "merged branch feat/x"
check "removes the worktree"               test ! -e "$W"
check "deletes its simulator"              bash -c "! grep -q kitchen-repo--w1 '$STUB_LOG.sims'"
check "removes the branch"                 bash -c "! git -C '$T/repo' rev-parse --verify -q feat/x"
check "removes the record"                 test ! -e "$T/data/state/w1"
check "closes the worker pane"             has "$(cat "$STUB_LOG")" "[pane] [close] [w1:p1]"
check "closes the check pane"              has "$(cat "$STUB_LOG")" "[pane] [close] [w2:p1]"

echo "# done --force"
"$K" worker w3 feat/k >/dev/null 2>&1
out=$("$K" "done" w3 --force 2>&1)
check "removes the worker"                 test ! -e "$T/data/worktrees/repo--w3"
check "keeps the unmerged branch"          git -C "$T/repo" rev-parse --verify -q feat/k

echo "# second machine"
export STUB_REMOTE_DATA="$T/remote"
printf 'REMOTE=true\nREMOTE_HOST=mini\nLOCAL_MAX=1\nREMOTE_KITCHEN=%q\n' "$K" > "$T/data/conf"
echo SECRET=1 > "$T/repo/.env"
RW="$T/remote/worktrees/origin--wr"
"$K" worker wl feat/l >/dev/null 2>&1
out=$("$K" worker wr feat/r 2>&1)
check "keeps workers here up to the limit"       bash -c "! grep -q '^ON=' '$T/data/state/wl'"
check "sends the second one over"          has "$out" "worker=wr"
check "says where it runs"                 has "$out" "on=mini"
check "records the machine"                grep -q '^ON=mini$' "$T/data/state/wr"
check "clones and branches over there"     test "$(git -C "$RW" branch --show-current)" = feat/r
check "copies the env file over"           test -f "$RW/.env"
check "makes no worktree here yet"         test ! -e "$T/data/worktrees/repo--wr"
"$K" worker ws feat/s --sim >/dev/null 2>&1
check "keeps a simulator worker here"      bash -c "! grep -q '^ON=' '$T/data/state/ws'"
echo "- [feat/l] from here" >> "$T/data/notes/repo.md"
echo "- [feat/r] from there" >> "$T/remote/notes/repo.md"
check "passes tell on"                     has "$("$K" tell wr hello 2>&1)" "sent to wr"
check "copies notes over"                  grep -q "from here" "$T/remote/notes/repo.md"
check "copies notes back"                  grep -q "from there" "$T/data/notes/repo.md"
check "passes wait on"                     has "$("$K" "wait" wr 2>&1)" "name=wr state=idle"
check "lists it with its machine"          has "$("$K" list 2>&1)" "wr  state=idle  branch=feat/r  on=mini"
check "refuses to check an unpushed branch" has "$("$K" check wr 2>&1)" "not on origin yet"
git -C "$RW" -c user.name=t -c user.email=t@t commit -q --allow-empty -m work
git -C "$RW" push -q origin feat/r
out=$("$K" check wr 2>&1)
check "checks the pushed branch here"      has "$out" "TESTS: 2/2"
check "checks the commit that was pushed"  test "$(git -C "$T/data/worktrees/repo--wr" rev-parse HEAD)" = "$(git -C "$RW" rev-parse HEAD)"
check "sends the results over"             test -f "$RW/.kitchen/card.txt"
sed -i '' 's/^REMOTE=true/REMOTE=false/' "$T/data/conf"
"$K" worker wo feat/o >/dev/null 2>&1
check "keeps every worker here when off"   bash -c "! grep -q '^ON=' '$T/data/state/wo'"
check "still reaches a worker over there"  has "$("$K" tell wr again 2>&1)" "sent to wr"
"$K" "done" wr --force >/dev/null 2>&1
check "removes it over there"              test ! -e "$RW"
check "removes its checkout here"          test ! -e "$T/data/worktrees/repo--wr"
check "removes its record here"            test ! -e "$T/data/state/wr"

echo
if [ "$fails" = 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
