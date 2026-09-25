#!/usr/bin/env bash
# =============================================================================
# Shared .env loader for Hoplon.
#
# `.env` is READ AS DATA, never sourced. Values are exported verbatim and are
# never passed through a shell: command substitution, backticks, and arithmetic
# do not run. On top of that, names that change how a child process loads code,
# resolves binaries, or finds its home are refused, so a poisoned `.env` cannot
# become host code execution through LD_PRELOAD, BASH_ENV, NODE_OPTIONS, and the
# like. The launcher, the installer, and the VM helper all call this one loader
# so the three stay identical.
#
# Usage:
#   . "<repo>/scripts/env.sh"
#   hoplon_load_env "<repo>/.env"
# =============================================================================
# shellcheck shell=bash

hoplon_load_env() {
  local _hl_file="$1"
  [ -f "$_hl_file" ] && [ -r "$_hl_file" ] || return 0
  local _hl_line _hl_name _hl_value

  while IFS= read -r _hl_line || [ -n "$_hl_line" ]; do
    _hl_line="${_hl_line%$'\r'}"
    [[ "$_hl_line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
    _hl_name="${_hl_line%%=*}"
    _hl_value="${_hl_line#*=}"
    case "$_hl_value" in
      \'*\') _hl_value="${_hl_value#\'}" && _hl_value="${_hl_value%\'}" ;;
      \"*\") _hl_value="${_hl_value#\"}" && _hl_value="${_hl_value%\"}" ;;
    esac

    case "$_hl_name" in
      LD_* | BASH_ENV | ENV | BASH_FUNC_* | PROMPT_COMMAND | GLOBIGNORE | \
        NODE_OPTIONS | NODE_PATH | NODE_REPL_EXTERNAL_MODULE | \
        PYTHONSTARTUP | PYTHONHOME | PYTHONPATH | PYTHONWARNINGS | \
        PERL5LIB | PERL5OPT | PERL5DB | PERL* | \
        RUBYOPT | RUBYLIB | GEM_HOME | GEM_PATH | \
        HOME | PATH | IFS | SHELL | CDPATH | PWD | OLDPWD | \
        TMPDIR | XDG_CONFIG_HOME | XDG_DATA_HOME | XDG_CACHE_HOME | \
        XDG_STATE_HOME | XDG_RUNTIME_DIR)
        printf 'hoplon: ignoring unsafe name %s in %s\n' "$_hl_name" "$_hl_file" >&2
        continue
        ;;
    esac

    export "$_hl_name=$_hl_value"
  done < "$_hl_file"

  unset _hl_line _hl_name _hl_value 2> /dev/null || true
  return 0
}
