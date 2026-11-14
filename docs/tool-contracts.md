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
  In a narrow pane much of it is interface decoration.
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

## git and gh

- Two `git worktree add` in one repository at the same moment can fail on git's config
  lock. kitchen creates worktrees one at a time.
- `git worktree add DIR BRANCH` checks out an existing local branch, or creates it
  from `origin/BRANCH` when only that exists.
- `gh pr view BRANCH --json state -q .state` prints `OPEN`, `MERGED`, or `CLOSED`, and
  fails when the branch has no pull request.

## Not yet observed on the real tools

- A complete `kitchen designer` run.
- A single check that runs longer than nine minutes (covered by the stub tests only).
