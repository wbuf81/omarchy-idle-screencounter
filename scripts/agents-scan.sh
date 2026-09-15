#!/usr/bin/env bash
# Summarize running coding agents as JSON for the Arrivals board.
#
# Output: one JSON array. Each record:
#   pid, agent (process name), label, strategy (claude|codex|generic), cwd,
#   started (epoch s), lastActivity (epoch s, 0 unknown), branch, tools
#   (last four tool names), sessionStatus (busy|idle|""), cpuTicks
#   (utime+stime from /proc), windowTitle (attributed from AGENTS_TITLES),
#   ancestors (up to three parent pids, so a terminal window can be matched).
#
# Environment:
#   AGENTS_EXTRA         comma-separated extra process names, treated as generic
#   AGENTS_TITLES        newline-separated "pid<TAB>title" candidates ("any" as
#                        the pid matches every record); a title is attributed
#                        to a Claude session when its text appears in the
#                        transcript
#   AGENTS_KNOWN         newline-separated "pid<TAB>title" attributions from a
#                        previous scan; reused without re-reading the transcript
#                        while that title is still among the candidates
#   AGENTS_SCAN_ONLY     comma-separated process names; restricts the table to
#                        exactly these names (tests)
#   AGENTS_SCAN_HOME     overrides $HOME (tests)
#   AGENTS_SCAN_LIBRARY  when non-empty, only define functions (tests)
#
# Only tool names, branch, cwd, timestamps, and caller-supplied titles leave
# this file. Message text is never read into the output.
set -uo pipefail

home="${AGENTS_SCAN_HOME:-$HOME}"
tail_bytes=400000

# process name | label | strategy
AGENT_TABLE="claude|Claude Code|claude
codex|Codex|codex
opencode|OpenCode|generic
aider|Aider|generic
gemini|Gemini CLI|generic
goose|Goose|generic
amp|Amp|generic
cursor-agent|Cursor|generic
copilot|Copilot CLI|generic"

# JSON string escaping. Control characters cannot be represented without
# \u escapes, so they are dropped: a stray OSC byte in some window's title
# must never take the whole board down.
json_escape() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/ }
  s=${s//$'\t'/ }
  s=${s//$'\r'/ }
  printf '%s' "$s" | tr -d '\000-\037\177'
}

json_string_array() {
  local out="" item
  for item in "$@"; do
    [[ -z $item ]] && continue
    out+="${out:+,}\"$(json_escape "$item")\""
  done
  printf '[%s]' "$out"
}

json_number_array() {
  local out="" item
  for item in "$@"; do
    [[ $item =~ ^[0-9]+$ ]] || continue
    out+="${out:+,}$item"
  done
  printf '[%s]' "$out"
}

cpu_ticks_for() {
  local stat
  stat=$(cat "/proc/$1/stat" 2>/dev/null) || { printf '0'; return; }
  stat=${stat##*) }
  # shellcheck disable=SC2086
  set -- $stat
  printf '%s' $(( ${12:-0} + ${13:-0} ))
}

# Up to three parent pids, nearest first. The Hyprland client pid for a CLI
# agent is usually its terminal, two hops up.
ancestors_for() {
  local pid=$1 out=() i stat
  for i in 1 2 3; do
    stat=$(cat "/proc/$pid/stat" 2>/dev/null) || break
    stat=${stat##*) }
    # shellcheck disable=SC2086
    set -- $stat
    pid=${2:-0}
    [[ $pid -le 1 ]] && break
    out+=("$pid")
  done
  printf '%s ' "${out[@]}"
}

# Claude Code titles its terminal with a status glyph and a summary, and that
# summary also appears inside the transcript. Return the first candidate
# title for this pid that carries a glyph and whose text is in the transcript.
# A plain title (no glyph) is some other window and is never attributed.
attribute_title() {
  local pid=$1 transcript=$2 tpid title text
  [[ -z ${AGENTS_TITLES:-} || -z $transcript || ! -r $transcript ]] && return
  # A previous scan already paid for the transcript read: keep its answer
  # while that window still exists.
  if [[ -n ${AGENTS_KNOWN:-} ]]; then
    while IFS=$'\t' read -r tpid title; do
      [[ $tpid != "$pid" || -z $title ]] && continue
      if grep -qF -- $'\t'"$title" <<< "$AGENTS_TITLES"; then printf '%s' "$title"; return; fi
    done <<< "$AGENTS_KNOWN"
  fi
  local needle
  while IFS=$'\t' read -r tpid title; do
    [[ $tpid != "$pid" && $tpid != any ]] && continue
    title=$(printf '%s' "$title" | tr -d '\000-\037\177')
    text=$(printf '%s' "$title" | sed -E 's/^[^[:alnum:]]+[[:space:]]*//')
    [[ -z $text || $text == "$title" ]] && continue
    # The transcript is JSON, so quotes and backslashes in the title appear
    # escaped there.
    needle=${text//\\/\\\\}
    needle=${needle//\"/\\\"}
    if grep -qF -m1 -- "$needle" "$transcript"; then
      printf '%s' "$title"
      return
    fi
  done <<< "$AGENTS_TITLES"
}

emit_record() {
  # pid agent label strategy cwd started lastActivity branch sessionStatus cpuTicks windowTitle ancestors tools...
  local pid=$1 agent=$2 label=$3 strategy=$4 cwd=$5 started=$6 last=$7 branch=$8 status=$9 cpu=${10} title=${11} ancestors=${12}
  shift 12
  # shellcheck disable=SC2086
  printf '{"pid":%s,"agent":"%s","label":"%s","strategy":"%s","cwd":"%s","started":%s,"lastActivity":%s,"branch":"%s","tools":%s,"sessionStatus":"%s","cpuTicks":%s,"windowTitle":"%s","ancestors":%s}' \
    "${pid:-0}" "$(json_escape "$agent")" "$(json_escape "$label")" "$strategy" "$(json_escape "$cwd")" \
    "${started:-0}" "${last:-0}" "$(json_escape "$branch")" "$(json_string_array "$@")" "$(json_escape "$status")" "${cpu:-0}" \
    "$(json_escape "$title")" "$(json_number_array $ancestors)"
}

summarize_claude() {
  local pid=$1 cwd=$2 started=$3 cpu=$4 ancestors=${5:-}
  local session="$home/.claude/sessions/$pid.json" sid="" status="" transcript="" last="" branch="" title=""
  local tools=()
  if [[ -r $session ]]; then
    sid=$(grep -oE '"sessionId":"[^"]+"' "$session" | head -1 | cut -d'"' -f4)
    status=$(grep -oE '"status":"[^"]+"' "$session" | head -1 | cut -d'"' -f4)
  fi
  # Claude Code names the project folder after the cwd with every character
  # outside [A-Za-z0-9] replaced by "-".
  local projdir="$home/.claude/projects/$(printf '%s' "$cwd" | sed 's#[^A-Za-z0-9]#-#g')"
  if [[ -n $sid && -r "$projdir/$sid.jsonl" ]]; then
    transcript="$projdir/$sid.jsonl"
  else
    transcript=$(ls -t "$projdir"/*.jsonl 2>/dev/null | head -1)
  fi
  if [[ -n $transcript ]]; then
    last=$(stat -c %Y "$transcript" 2>/dev/null)
    mapfile -t tools < <(tail -c "$tail_bytes" "$transcript" | grep -oE '"type":"tool_use","id":"[^"]+","name":"[A-Za-z0-9_]+"' | grep -oE '"name":"[A-Za-z0-9_]+"' | tail -4 | cut -d'"' -f4)
    branch=$(tail -c 20000 "$transcript" | grep -oE '"gitBranch":"[^"]*"' | tail -1 | cut -d'"' -f4)
    title=$(attribute_title "$pid" "$transcript")
  fi
  emit_record "$pid" claude "Claude Code" claude "$cwd" "$started" "${last:-0}" "$branch" "$status" "$cpu" "$title" "$ancestors" "${tools[@]}"
}

summarize_codex() {
  local pid=$1 cwd=$2 started=$3 cpu=$4 ancestors=${5:-} transcript="" last="" f
  local tools=()
  for f in $(ls -t "$home"/.codex/sessions/*/*/*/rollout-*.jsonl 2>/dev/null | head -40); do
    if head -c 4000 "$f" | grep -qF "\"cwd\":\"$cwd\""; then transcript=$f; break; fi
  done
  if [[ -n $transcript ]]; then
    last=$(stat -c %Y "$transcript" 2>/dev/null)
    mapfile -t tools < <(tail -c "$tail_bytes" "$transcript" | grep -oE '"type":"function_call"[^}]{0,300}"name":"[A-Za-z0-9_]+"' | grep -oE '"name":"[A-Za-z0-9_]+"' | tail -4 | cut -d'"' -f4)
  fi
  emit_record "$pid" codex Codex codex "$cwd" "$started" "${last:-0}" "" "" "$cpu" "" "$ancestors" "${tools[@]}"
}

summarize_generic() {
  local pid=$1 agent=$2 label=$3 cwd=$4 started=$5 cpu=$6 ancestors=${7:-}
  emit_record "$pid" "$agent" "$label" generic "$cwd" "$started" 0 "" "" "$cpu" "" "$ancestors"
}

scan() {
  local table="$AGENT_TABLE" name records=() proc label strategy pid cwd started cpu ancestors
  local extra="${AGENTS_EXTRA:-}"
  if [[ -n ${AGENTS_SCAN_ONLY:-} ]]; then
    table=""
    for name in ${AGENTS_SCAN_ONLY//,/ }; do
      [[ $name =~ ^[a-z0-9._-]+$ ]] || continue
      table+="${table:+$'\n'}$name|$name|generic"
    done
  fi
  for name in ${extra//,/ }; do
    [[ $name =~ ^[a-z0-9._-]+$ ]] || continue
    grep -q "^$name|" <<< "$table" || table+=$'\n'"$name|$name|generic"
  done
  while IFS='|' read -r proc label strategy; do
    [[ -z $proc ]] && continue
    for pid in $(pgrep -x -- "$proc" 2>/dev/null); do
      cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null) || continue
      started=$(stat -c %Y "/proc/$pid" 2>/dev/null || printf 0)
      cpu=$(cpu_ticks_for "$pid")
      ancestors=$(ancestors_for "$pid")
      case $strategy in
        claude) records+=("$(summarize_claude "$pid" "$cwd" "$started" "$cpu" "$ancestors")") ;;
        codex) records+=("$(summarize_codex "$pid" "$cwd" "$started" "$cpu" "$ancestors")") ;;
        *) records+=("$(summarize_generic "$pid" "$proc" "$label" "$cwd" "$started" "$cpu" "$ancestors")") ;;
      esac
    done
  done <<< "$table"
  local joined="" r
  for r in "${records[@]}"; do joined+="${joined:+,}$r"; done
  printf '[%s]\n' "$joined"
}

if [[ -z ${AGENTS_SCAN_LIBRARY:-} ]]; then
  scan
fi
