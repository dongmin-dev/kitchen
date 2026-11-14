# Source this file from ~/.zshrc:   source ~/Agents/kitchen/kitchen.zsh
export KITCHEN_HOME="${0:A:h}"
path=("$KITCHEN_HOME/bin" $path)

# chef — start the orchestrator in the current project. Run it inside Herdr.
chef() {
  if [[ "$HERDR_ENV" != 1 ]]; then
    echo "chef: start herdr first, then run chef inside it."
    return 1
  fi
  source "$KITCHEN_HOME/kitchen.conf"
  claude "$@" \
    --model "$CHEF_MODEL" --effort "$CHEF_EFFORT" \
    --append-system-prompt-file "$KITCHEN_HOME/roles/orchestrator.md" \
    --allowedTools "Bash(kitchen *)" "Bash(herdr agent *)" "Bash(git status*)" "Bash(git log*)" "Bash(git diff*)" "Bash(gh pr view*)" "Bash(gh pr list*)" "Bash(gh issue *)" \
    --disallowedTools "Agent" "Edit" "Write" "NotebookEdit" "mcp__*"
}
