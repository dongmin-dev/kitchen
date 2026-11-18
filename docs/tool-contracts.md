# Tool contracts

What kitchen relies on in the tools it drives. Everything here was observed on the
versions below, not taken from documentation. When a tool update breaks kitchen, compare
against this list first, and update the list when behaviour changes.

Observed in November 2026 on macOS with Herdr 0.9.5, Claude Code 2.1.311, and
codex-cli 0.167.2.

## Herdr

- The `herdr` command works from any shell on the machine while the Herdr app runs.
  Panes inside Herdr have `HERDR_ENV=1`; kitchen refuses to run without it.
- `herdr workspace list` → `.result.workspaces[]` with `workspace_id` and `label`.
- `herdr workspace create --cwd DIR --label TEXT --no-focus` →
  `.result.workspace.workspace_id` and `.result.root_pane.pane_id`.
- `herdr pane list --workspace ID` → `.result.panes[]` with `pane_id`.
- `herdr pane layout --pane ID` → `.result.layout.panes[]` with `pane_id` and
  `rect.{width,height}` in terminal cells, for every pane of that tab.
- `herdr pane split PANE --direction right|down --cwd DIR --no-focus` →
  `.result.pane.pane_id`.
- `herdr pane rename PANE LABEL` sets the label shown on the pane.
- `herdr pane get PANE` has `.result` for a live pane and `.error` for a closed one.
- `herdr pane close PANE` ends whatever runs in it. Closing the last pane of a
  workspace closes the workspace.
- `herdr pane run PANE COMMAND` types the command into the pane's shell and returns at
  once; it does not report whether the command ran or how it ended.
- `herdr agent start NAME --kind claude --pane PANE --timeout MS -- ARGS` types
  `claude ARGS` into the pane's shell, so shell aliases for `claude` apply. Errors seen:
  `agent_pane_busy` (the pane's shell is not ready yet; retry), `agent_not_ready`
  (Claude Code is waiting at a startup dialog, for example folder trust),
  `agent_name_taken`.
- Agent names match `[a-z][a-z0-9_-]{0,31}`.
- `herdr agent get NAME` → `.result.agent.agent_status` (`idle`, `working`, `blocked`,
  `done`, `unknown`) and `.result.agent.pane_id`.
- `herdr agent prompt NAME TEXT` sends a prompt. The status changes to `working` a
  moment later, so kitchen waits for that before returning.
- `herdr agent wait NAME [--until STATUS] [--timeout MS]` blocks until the agent stops
  working or the timeout passes.
- `herdr agent read NAME --source recent-unwrapped --lines N` returns the pane's text.
  Much of it is interface decoration, and when the pane is scrolled up it is old text.
  kitchen uses it only as a fallback.
- `herdr agent get NAME` also has `.result.agent.agent_session.value`, the id of the
  Claude Code session running in the pane.
- `herdr <group>` with no subcommand lists that group's commands; `herdr api schema
  --json` describes every request and response.

## Claude Code

- `--dangerously-skip-permissions` removes permission prompts. Passing it twice is
  accepted.
- It does not skip the folder trust dialog. The dialog appears for a repository that
  was never opened in Claude Code, even when the parent folder is trusted. It does not
  appear for a git worktree of a trusted repository, wherever the worktree is.
- Trust is recorded in `~/.claude.json` as `.projects["<path>"].hasTrustDialogAccepted`.
  kitchen only reads this, in `kitchen doctor`.
- `--tools "A,B,C"` limits the session to exactly those built-in tools.
  `--strict-mcp-config` without `--mcp-config` gives a session with no MCP tools.
- `--append-system-prompt-file FILE` adds the file to the system prompt. It is not
  shown in `claude --help`.
- `--tools`, `--allowedTools`, and `--disallowedTools` take several values and will
  swallow a prompt placed after them; put a prompt first.
- A session is recorded in `~/.claude/projects/<folder>/<session id>.jsonl`, one JSON
  object per line. Assistant turns have `type: "assistant"` and
  `message.content[]` items; the ones with `type: "text"` are what the agent said.
  `kitchen tail` reads the last of these.
- An alias named `claude` is expanded by zsh when a function is defined. `chef` calls
  `command claude` to avoid that.

## Codex

- `-c key=value` overrides `~/.codex/config.toml`. An unquoted value is taken as a
  string, so `-c approval_policy=never -c sandbox_mode=danger-full-access` works.
- `codex review --base BRANCH` prints the verdict on stdout and the whole run (often
  hundreds of kilobytes) on stderr. Exit code 0 on success.
- A review without findings is one paragraph. A review with findings looks like this:

      Full review comments:

      - [P1] <title> — <absolute path>:<first line>-<last line>
        <explanation>

  Priorities seen: `P1`, `P2`. The orchestrator treats `P0` and `P1` as must-fix.
- `codex exec "PROMPT"` runs one task without interaction and exits. It prints its
  progress, including MCP tool calls, to the terminal.
- When the usage limit is reached, the run ends with `ERROR: You've hit your usage
  limit ... try again at <time>` and a non-zero exit code. kitchen reports this as a
  tool problem and redoes the run on the next `kitchen check`.
- `codex mcp list` lists configured MCP servers; `codex login status` exits 0 when
  logged in.
- `codex exec` waits for input when stdin is open and not a terminal. In a Herdr pane it
  is a terminal; a script that runs `kitchen _check` directly must add `</dev/null`.

## Xcode and agent-device (iOS checks)

Observed with Xcode 27.2 and agent-device 0.21.37.

- `xcrun simctl create NAME "iPhone 17"` creates a simulator on the newest installed
  runtime and prints its id. `simctl boot ID` returns at once and `simctl bootstatus ID`
  waits until it is usable (about 30 seconds the first time). No Simulator window opens.
- `simctl list devices` prints one `NAME (ID) (Booted|Shutdown)` line per simulator.
- `xcodebuild -destination "platform=iOS Simulator,id=ID"` builds for one simulator.
  A destination given by name picks whichever matching simulator comes first.
- `agent-device open APP --udid ID`, `snapshot -i`, `press`, `fill`, and `screenshot`
  drive an app on that simulator from the shell, without any MCP configuration.
- A Codex tester given `kitchen sim` built a SwiftUI app, installed it, walked a flow,
  and reported a wrong value on screen with screenshots, in under four minutes.
- An Expo app with no `ios/` folder needs CocoaPods for its native build
  (`brew install cocoapods`); the Ruby that ships with macOS is too old to install it.
- With CocoaPods present, a Codex tester built an Expo app (no `ios/` folder in the
  repository) for its simulator and walked the sign-in flow on web and on iOS. The
  first native build made the whole check take about twelve minutes, longer
  than one `kitchen check` waits.

## A second machine (Herdr machines and SSH)

Observed between two Macs with Herdr 0.9.5 on both.

- A machine saved with `herdr machine add NAME` shows its workspaces and agents in the
  local Herdr window. `herdr --machine NAME <command>` runs an API command there, and
  `herdr machine status` prints `reachable` for it.
- `ssh NAME 'zsh -lc "HERDR_ENV=1 kitchen ..."'` reaches the Herdr server of that
  machine from outside any pane; a login shell is needed for the Homebrew `PATH`.
- A worker started this way took a prompt, pushed its branch, and was checked on the
  first machine; `tell` took about 25 seconds and the whole start about 45.
- The clone that kitchen makes on the second machine is new to Claude Code, so the first
  worker in it stops at the trust dialog (`agent_not_ready`). The dialog's default
  answer is "No, exit". After it is accepted once, the same worker continues with
  `kitchen tell`.

## git and gh

- Two `git worktree add` in one repository at the same moment can fail on git's config
  lock. kitchen creates worktrees one at a time.
- `git worktree add DIR BRANCH` checks out an existing local branch, or creates it
  from `origin/BRANCH` when only that exists.
- `git worktree remove --force DIR` has stopped partway through a worktree of several
  gigabytes (inside `node_modules`) and still removed its entry from the repository, on
  three workers of one project. The cause is not known; `kitchen done` deletes the
  rest itself.
- `gh pr view BRANCH --json state -q .state` prints `OPEN`, `MERGED`, or `CLOSED`, and
  fails when the branch has no pull request.

- A designer started with `kitchen designer` loads the Figma skill, reads a file, and
  writes to it (variables, text styles, components, frames) through the Figma MCP
  server configured in Claude Code.

## Not yet observed on the real tools

- `kitchen check` answering `STILL RUNNING` for a check longer than nine minutes (the
  long iOS check above was started directly; covered by the stub tests only).
- Two iOS checks running at the same time, and a third waiting for `SIM_MAX`
  (covered by the stub tests only).
