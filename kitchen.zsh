# Source this file from ~/.zshrc:   source ~/Agents/kitchen/kitchen.zsh
export KITCHEN_HOME="${0:A:h}"
path=("$KITCHEN_HOME/bin" $path)

# chef — start the orchestrator in the current project. Run it inside Herdr.
chef() {
  if [[ "$HERDR_ENV" != 1 ]]; then
    echo "chef: start herdr first, then run chef inside it."
    return 1
  fi
  # The same three settings files as bin/kitchen, later ones winning.
  local f data="${KITCHEN_DATA:-$HOME/.kitchen}"
  for f in "$KITCHEN_HOME/kitchen.conf" "$data/conf" "$data/projects/${PWD:t}.conf"; do
    [[ -f "$f" ]] && source "$f"
  done
  # "command" skips any claude alias, so the flags below are the whole story.
  # KITCHEN_PROJECT names the shared notes file, wherever kitchen is called from later.
  KITCHEN_PROJECT="$PWD" command claude "$@" \
    --model "$CHEF_MODEL" --effort "$CHEF_EFFORT" \
    --dangerously-skip-permissions \
    --append-system-prompt-file "$KITCHEN_HOME/roles/orchestrator.md" \
    --strict-mcp-config \
    --tools "$CHEF_TOOLS"
}
