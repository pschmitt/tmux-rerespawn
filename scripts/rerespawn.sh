#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") [PANE_ID]"
}

get_default_shell() {
  local default_shell

  default_shell="$(tmux show-option -gqv "default-shell")"

  if [[ -z "$default_shell" ]]
  then
    default_shell="${SHELL:-$(command -v sh)}"
  fi

  echo "$default_shell"
}

get_current_pane_id() {
  get_current_pane_info | awk '{ print $1 }'
}

get_current_pane_info() {
  tmux display -p '#{pane_id} #{pane_pid}'
}

get_pane_pid_from_pane_id() {
  tmux list-panes -F "#{pane_id} #{pane_pid}" | awk "/^$1 / { print \$2}"
}

get_pane_path_from_pane_id() {
  # We're using sed here since the current path may contain spaces
  tmux list-panes -F "#{pane_id} #{pane_current_path}" | \
    sed -rn "s/^${1} (.+)/\1/p"
}

get_pane_command() {
  local child_cmd
  local pane_id
  local pane_pid

  pane_id="${1:-$(get_current_pane_id)}"
  pane_pid="$(get_pane_pid_from_pane_id "$pane_id")"

  if [[ -z "$pane_pid" ]]
  then
    echo "Could not determine pane PID" >&2
    return 3
  fi

  local shell
  shell="$(get_default_shell)"

  ps -o pid=,command= -g "${pane_pid}" | while read -r child_pid child_cmd
  do
    if [[ -n "$DEBUG" ]]
    then
      echo -n "Checking ($child_pid) -> $child_cmd" >&2
    fi

    case "$child_cmd" in
      # -zsh|/home/pschmitt/.cache/gitstatus/gitstatusd-linux-x86_64 ...
      -"${shell}"|-"$(basename "$shell")"|"${SHELL}"|*gitstatusd-*|*"$0"*)
        if [[ -n "$DEBUG" ]]
        then
          echo " [SKIP]" >&2
        fi
        continue
        ;;
    esac

    # FIXME When child_cmd is:
    # zsh -c trap "/bin/zsh" EXIT INT; zsh nvim XXX
    # The kill -0 check will return true, even if nvim is not running any more
    # -> nvim will be in the foreground after rerespawning the pane even though
    # the user quit nvim
    # FIXME Shouldn't we return here, if the child cmd is not alive so that we
    # spawn a new shell instead of whatever is running under the dead PID?
    if kill -0 "$child_pid"
    then
      if [[ -n "$DEBUG" ]]
      then
        echo " [!ALIVE!]" >&2
      fi

      echo "$child_cmd"
      return
    fi
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  while [[ -n "$*" ]]
  do
    case "$1" in
      help|h|-h|--help)
        usage
        exit 0
        ;;
      -d|--debug)
        DEBUG=1
        shift
        ;;
      -k|--dry-run)
        DRY_RUN=1
        shift
        ;;
      -w|--wrap)
        WRAP=1
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  pane_id="$1"
  if ! pane_cmd=$(get_pane_command "$pane_id")
  then
    exit 1
  fi

  default_shell="$(get_default_shell)"

  if [[ -z "$pane_cmd" ]]
  then
    {
      echo "It seems that there is no running command in pane" \
        "${1:-$(get_current_pane_id)}"
      echo "Spawning a new regular pane instead"
    } >&2
  fi

  extra_args=(-k)

  if [[ -n "$pane_id" ]]
  then
    extra_args+=(-t "$pane_id")
  fi

  pane_path=$(get_pane_path_from_pane_id "$pane_id")

  if [[ -n "$pane_path" ]]
  then
    extra_args+=(-c "$pane_path")
  fi

  if [[ -n "$pane_cmd" ]]
  then
    if [[ -n "$WRAP" ]]
    then
      cmd_prefix="trap \"${default_shell}\" EXIT INT"

      # Avoid prefixing an already prefixed command (when respawning the same
      # pane 2+ times)
      if ! [[ "$pane_cmd" =~ ${cmd_prefix} ]]
      then
        pane_cmd="${cmd_prefix}; ${pane_cmd}"
      fi
    fi

    extra_args+=("$pane_cmd")
  fi

  if [[ -n "$DRY_RUN" ]] || [[ -n "$DEBUG" ]]
  then
    echo tmux respawn-pane "${extra_args[@]}"
  fi

  if [[ -z "$DRY_RUN" ]]
  then
    tmux respawn-pane "${extra_args[@]}"
  fi
fi
