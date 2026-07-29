#!/usr/bin/env bash
# Scope-gated bounded dispatcher. Task file rows: id<TAB>colon:scopes<TAB>command.

validate_task_scopes() {
  local file="$1" ids scopes id scope seen_id seen_scope
  ids=""; scopes=""
  while IFS="$(printf '\t')" read -r id scope _; do
    [[ -n "$id" && -n "$scope" ]] || return 2
    case " $ids " in *" $id "*) return 2 ;; esac
    ids="$ids $id"
    old_ifs="$IFS"; IFS=':'
    for seen_scope in $scope; do
      case " $scopes " in *" $seen_scope "*) IFS="$old_ifs"; return 3 ;; esac
      scopes="$scopes $seen_scope"
    done
    IFS="$old_ifs"
  done < "$file"
}

dispatch_tasks() {
  local max="$1" file="$2" id scope command pid pids="" running=0 rc=0
  case "$max" in ''|*[!0-9]*|0) return 2 ;; esac
  validate_task_scopes "$file" || return $?
  while IFS="$(printf '\t')" read -r id scope command; do
    bash -c "$command" &
    pid=$!; pids="$pids $pid"; running=$((running + 1))
    if [[ "$running" -ge "$max" ]]; then
      set -- $pids; wait "$1" || rc=1; shift
      pids="$*"; running=$((running - 1))
    fi
  done < "$file"
  for pid in $pids; do wait "$pid" || rc=1; done
  return "$rc"
}
