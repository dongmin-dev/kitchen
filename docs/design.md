# Design

Why kitchen is built the way it is. Read this before changing how it works.

## The problem

A strong model is good at planning and judging, but it is expensive and its weekly
allowance is small. If the same session also writes the code, reads every diff, and
looks at every screenshot, it runs out of both context and allowance. A second problem
is that a model reviewing its own work tends to agree with itself.

kitchen splits the work across three kinds of agent:

| Role | Model | Does |
|---|---|---|
| Orchestrator (`chef`) | Claude Fable, medium effort | Plans, splits, delegates, decides from short results |
| Worker, designer | Claude Opus | Writes the code, or builds the design in Figma |
| Reviewer, tester | Codex (a different vendor's model) | Reviews the diff, runs the tests, walks the user flow |

## Decisions

**Roles are part of the start command, not of `CLAUDE.md`.** Each agent gets its role
through `--append-system-prompt-file roles/<role>.md` (the tester is told to read its
file). The workflow is then the same in every project, a project's own `CLAUDE.md`
stays about the project, and an agent cannot pick up another agent's role.

**The orchestrator has a fixed, short tool list.** It is started with
`--tools "Bash,Read,Grep,Glob,WebSearch,WebFetch"` and `--strict-mcp-config`: no
subagents, no file editing, no MCP tools. It cannot do the work itself even if it wants
to, so it has to delegate. What it does with Bash is limited by its instructions.

**No agent asks for permission.** Agents run unattended in panes; a permission prompt
would stop the loop with nobody there to answer. kitchen passes the flags itself
(`--dangerously-skip-permissions` for Claude Code, `approval_policy=never` and
`sandbox_mode=danger-full-access` for Codex), so the behaviour is the same on every
machine and does not depend on shell aliases or on `~/.codex/config.toml`. The
consequence is that agents can do anything your user account can. Use kitchen only on
machines and repositories where that is acceptable.

**One worker, one worktree, one branch, one pull request.** Workers run in parallel
without touching each other's files. Worktrees live in `~/.kitchen/worktrees/`,
outside both the project and the kitchen install, so updating kitchen can never delete
work in progress.

**The orchestrator reads results, not transcripts.** `kitchen check` prints a review
verdict of a few lines and a test card of six lines. The reviewer's full run goes to
`.kitchen/review.log` and the tester's to `.kitchen/test.log`, for people to read.
This is what keeps the orchestrator's context and allowance small.

**A commit is checked once.** `kitchen check` stores the result under the commit it
checked. Asking again waits for a run in progress or prints the stored result; a new
commit starts a new run. A run that broke (Codex failed, or no test card was written)
is not a result and is redone on the next call, keeping a review that succeeded.

**Review and test run as plain commands in a pane.** `codex review` and `codex exec`
start, finish, and exit. There is no long-lived reviewer or tester agent whose state
has to be tracked, and each run starts without memory of the previous one.

**Two Herdr workspaces per project.** `<project> workers` holds one pane per worker
or designer, `<project> checks` one pane per worker for its reviews and tests. You see
all the builders in one place and all the verification in another.

**Agents never merge.** The loop ends with pull requests that are ready. Merging is
the one step that changes the shared history, and it stays with a person. `kitchen
done` removes a worker only after its pull request is merged, unless `--force` is given.

**Workers share facts through one notes file.** `~/.kitchen/notes/<project>.md` is
linked into every worktree as `.kitchen/notes.md`. Workers in different repositories
of one project use it to agree on API shapes, names, and ports without going through
the orchestrator.

**Small and plain.** One bash script that works with the bash 3.2 shipped with macOS,
one config file, four role files. State is one small file per worker. When something
is wrong, the fix should make the tool smaller or leave it the same size.

**A second machine is the same tool again.** With `REMOTE_HOST` set, a worker that
does not need the simulator goes to the machine with fewer workers. kitchen on the first
machine does not reimplement anything for it: it calls kitchen on the second machine over
SSH (`worker`, `tell`, `wait`, `tail`, `done`), and Herdr shows that machine's panes next
to the local ones. Reviews and tests stay on the first machine, in a checkout of what
the worker pushed; the verdict and the card are copied back for the worker to read. The
notes file exists on both machines and missing lines are copied each way on `tell` and
`wait`.

## Limits

- The orchestrator's restraint with Bash is an instruction, not an enforced rule.
- The tester's browser check needs the Playwright MCP server configured in Codex.
- The tester's iOS check needs Xcode with a simulator runtime and `agent-device`
  (and CocoaPods for Expo or React Native apps). Each worker gets its own simulator so
  that parallel checks cannot overwrite each other's app; `SIM_MAX` keeps only a few
  running, because every simulator and Xcode build takes a large share of a laptop.
- kitchen depends on the command-line behaviour of Herdr, Claude Code, and Codex.
  What it relies on is listed in [tool-contracts.md](tool-contracts.md).
