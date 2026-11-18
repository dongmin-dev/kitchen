# kitchen

A small tool that runs a team of coding agents inside [Herdr](https://github.com/herdrdev/herdr):
a Claude Fable orchestrator that plans and delegates, Claude Opus workers that write the
code, and Codex as an independent reviewer and tester.

Each agent's role is part of the command that starts it, so the workflow is the same in
every project and nothing has to be repeated in prompts or in `CLAUDE.md`.

## How it works

`chef` starts the orchestrator in the current project. It has no subagents, no
file-editing tools, and no MCP tools; the only way it can act is the `kitchen` command:

| Command | What it does |
|---|---|
| `kitchen worker <name> <branch> [medium\|high] [--repo <path>] [--sim]` | New git worktree and branch (an existing branch is continued), Opus worker started in a new pane |
| `kitchen designer <name> [medium\|high]` | Opus designer for Figma work in the current folder |
| `kitchen tell <name> "<instruction>"` | Send a prompt to a worker or designer |
| `kitchen wait <name>` | Wait until the agent stops working, print its state |
| `kitchen check <worker>` | Codex review against the base branch, then a Codex tester that runs the test suite and walks the user flow (web with Playwright, iOS in a simulator); prints the verdict and a short test card |
| `kitchen sim` | For the tester: the id of this worktree's iOS simulator, created and booted on first use |
| `kitchen app` | For the tester: the iOS Simulator app of an Expo project with this worktree's JavaScript in it. The native part is built once per fingerprint, on the second machine when there is one |
| `kitchen tail <name> [lines]` | The agent's last message (first lines of it) |
| `kitchen list` | Workers and their current state |
| `kitchen done <name> [--force]` | After the pull request is merged: close the panes, remove the worktree and the branch |
| `kitchen conf` | The settings in force for this project and the file each comes from |
| `kitchen doctor` | Check that everything kitchen needs is installed |

The loop the orchestrator follows is in [`roles/orchestrator.md`](roles/orchestrator.md):
plan, start workers in parallel, wait, check, send findings back, and stop when a
decision is needed or the pull requests are ready. Agents never merge; you do.

In Herdr a project takes two workspaces next to the orchestrator's own:
`<project> workers`, with one pane per worker or designer, and `<project> checks`, with
one pane per worker where its reviews and tests run. Panes are labelled with the worker's
name and tiled automatically; `<project>` is the folder `chef` was started in.

`kitchen check` checks a commit once: running it again for the same commit prints the
stored result.

Every agent runs without permission prompts. kitchen passes the flags for that itself.

## Files

- `kitchen.zsh` defines `chef` and puts `bin/` on the `PATH`.
- `kitchen.conf` holds the default of every setting (models, effort levels, limits).
  Change a setting in `~/.kitchen/conf` (this machine) or in
  `~/.kitchen/projects/<project>.conf` (one project; the name is the folder `chef` is
  started in), never in `kitchen.conf` itself. The project file wins over the machine
  file, which wins over the defaults. `kitchen conf` prints the values in force.
- `roles/*.md` are the instructions each agent starts with.
- `bin/kitchen` is the command.
- Runtime data lives outside this folder in `~/.kitchen/`: worktrees, worker records,
  and one shared notes file per project that is linked into every worktree as
  `.kitchen/notes.md`.

## Install

Requires `git`, `jq`, `gh` (logged in), `herdr`, `claude`, and `codex`.

    git clone https://github.com/dongmin-dev/kitchen.git ~/Agents/kitchen
    echo 'source ~/Agents/kitchen/kitchen.zsh' >> ~/.zshrc

Open a new shell, start `herdr`, and run `kitchen doctor` inside it.

Optional, for testing iOS apps (native or Expo): Xcode with an iOS simulator runtime,
selected with `sudo xcode-select -s /Applications/Xcode.app`, and
`npm install -g agent-device`. Each worker gets its own simulator; `SIM_MAX` in
`kitchen.conf` limits how many run at once.

Optional, a second machine for workers: install kitchen there the same way, save it in
Herdr on the first machine (`herdr machine add <ssh name>`), and write
`REMOTE=true` and `REMOTE_HOST=<ssh name>` to `~/.kitchen/conf` on the first machine
(`REMOTE=false` turns it off again; workers already there keep working). The first four
workers (`LOCAL_MAX`) still run on the first machine; further ones go to the second,
and all show up in the one Herdr window. Reviews, tests, and
workers started with `--sim` stay on the first machine. The second machine clones each
repository into `~/.kitchen/repos/`; open each clone once with `claude` there to accept
the trust dialog.

With a second machine, the native iOS builds of Expo apps are made there too. It needs
Xcode, Node, and CocoaPods in the shell that `ssh <name> 'zsh -lc ...'` starts (for a
Node from nvm and an Xcode not chosen with `xcode-select`, put the nvm lines and
`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` in `~/.zprofile`
there). `BUILD_DIR` in its `~/.kitchen/conf` moves the build folders to another disk.

Open each repository once with `claude` and accept the trust dialog. Worktrees of a
trusted repository start without asking.

`kitchen doctor` also reports whether the repository you are in, or the repositories
directly inside the current folder, are trusted.

Why kitchen works this way is in [docs/design.md](docs/design.md). What it relies on in
Herdr, Claude Code, and Codex is in [docs/tool-contracts.md](docs/tool-contracts.md).

Update with `git -C ~/Agents/kitchen pull`. Remove by deleting the folder and the
`source` line.

## License

[MIT](LICENSE)
