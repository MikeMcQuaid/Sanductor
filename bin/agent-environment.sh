#!/bin/sh
# Git runs post-checkout inside a newly added worktree, including in another repository.
# Named hooks coexist with the repository's hooks and apply only to this agent's processes.
# The hook expands this in the agent's Git process.
# shellcheck disable=SC2016
sanductor_record='/usr/bin/xattr -sw com.mikemcquaid.Sanductor.agent "$SANDUCTOR_WORKTREE_AGENT" .git 2>/dev/null || :'
for sanductor_event in post-checkout post-commit; do
  export "GIT_CONFIG_KEY_${GIT_CONFIG_COUNT:-0}=hook.sanductor-agent.event"
  export "GIT_CONFIG_VALUE_${GIT_CONFIG_COUNT:-0}=${sanductor_event}"
  GIT_CONFIG_COUNT=$((${GIT_CONFIG_COUNT:-0} + 1))
done
export "GIT_CONFIG_KEY_${GIT_CONFIG_COUNT}=hook.sanductor-agent.command"
export "GIT_CONFIG_VALUE_${GIT_CONFIG_COUNT}=${sanductor_record}"
GIT_CONFIG_COUNT=$((GIT_CONFIG_COUNT + 1))
export GIT_CONFIG_COUNT
/bin/sh -c "${sanductor_record}"
unset sanductor_record sanductor_event
