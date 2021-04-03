#!/usr/bin/env bash

get_tmux_option() {
  local option="$1"
  local default_value="$2"
  local raw_value

  raw_value=$(tmux show-option -gqv "$option")

  echo "${raw_value:-$default_value}"
}

main() {
  local -a extra_args

  local wrap
  wrap="$(get_tmux_option @respawn-wrap)"

  case "$wrap" in
    true|1|yes)
      extra_args+=(--wrap)
      ;;
  esac

  local key
  key="$(get_tmux_option @respawn-key)"

  if [[ -n "$key" ]]
  then
    local current_dir
    local script_path
    current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    script_path="${current_dir}/scripts/respawn.sh"

    tmux unbind "$key"
    tmux bind-key "$key" run "${script_path} ${extra_args[*]}"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main
fi

# vim: set ft=bash et ts=2 sw=2 :
