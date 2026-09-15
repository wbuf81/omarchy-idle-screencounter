#!/usr/bin/env bash
# Exercises the record builders against a fixture home. Process enumeration
# needs a live agent, so this covers parsing, not pgrep.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/.claude/sessions" "$fixture/.claude/projects/-home-wes-Projects-demo-app" "$fixture/.codex/sessions/2026/09/13"
cat > "$fixture/.claude/sessions/4242.json" <<'JSON'
{"pid":4242,"sessionId":"abc-123","cwd":"/home/wes/Projects/demo.app","startedAt":1789324406662,"name":"demo-app-1","status":"idle","updatedAt":1789324720849}
JSON
transcript="$fixture/.claude/projects/-home-wes-Projects-demo-app/abc-123.jsonl"
printf '%s\n' \
  '{"type":"user","cwd":"/home/wes/Projects/demo.app","gitBranch":"feature/x","message":{"role":"user","content":"Fix the thing"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{}}]}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Edit","input":{}}]}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done. Title hint: Demo app cleanup"}]}}' > "$transcript"
cat > "$fixture/.codex/sessions/2026/09/13/rollout-2026-09-13T10-00-00-xyz.jsonl" <<'JSON'
{"timestamp":"2026-09-13T10:00:00Z","type":"session_meta","payload":{"session_id":"xyz","cwd":"/home/wes/Projects/ledger"}}
{"timestamp":"2026-09-13T10:00:05Z","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{}"}}
{"timestamp":"2026-09-13T10:00:09Z","type":"response_item","payload":{"type":"function_call","name":"apply_patch","arguments":"{}"}}
JSON

export AGENTS_SCAN_HOME="$fixture" AGENTS_SCAN_LIBRARY=1
# shellcheck source=../scripts/agents-scan.sh
source "$here/../scripts/agents-scan.sh"

record=$(AGENTS_TITLES=$'4242\t✳ Demo app cleanup\n4242\t✳ Other window' summarize_claude 4242 /home/wes/Projects/demo.app 1789324406 12345 "100 4685")
echo "$record" | jq -e '.agent == "claude" and .strategy == "claude" and .branch == "feature/x" and .sessionStatus == "idle" and .cpuTicks == 12345 and (.tools == ["Read","Edit"]) and .windowTitle == "✳ Demo app cleanup" and (.ancestors == [100,4685])' >/dev/null

record=$(summarize_codex 777 /home/wes/Projects/ledger 1789324406 5 "")
echo "$record" | jq -e '.agent == "codex" and .strategy == "codex" and (.tools == ["shell","apply_patch"]) and .lastActivity > 0 and (.ancestors == [])' >/dev/null

record=$(summarize_generic 888 aider Aider /home/wes/Projects/anything 1789324406 9 "")
echo "$record" | jq -e '.agent == "aider" and .label == "Aider" and .strategy == "generic" and .tools == [] and .cpuTicks == 9' >/dev/null

# A matched title with quotes and a control byte survives JSON escaping.
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Working on the \"quoted\" board"}]}}' >> "$transcript"
record=$(AGENTS_TITLES="$(printf 'any\t\xe2\x9c\xb3 the "quoted" board\x01')" summarize_claude 4242 /home/wes/Projects/demo.app 1789324406 1 "")
echo "$record" | jq -e '.windowTitle == "✳ the \"quoted\" board"' >/dev/null

# A known attribution is reused while the window still exists, and dropped once it is gone.
record=$(AGENTS_TITLES=$'any\t✳ Demo app cleanup' AGENTS_KNOWN=$'4242\t✳ Demo app cleanup' summarize_claude 4242 /home/wes/Projects/demo.app 1789324406 1 "")
echo "$record" | jq -e '.windowTitle == "✳ Demo app cleanup"' >/dev/null
record=$(AGENTS_TITLES=$'any\t✳ Something else' AGENTS_KNOWN=$'4242\t✳ Gone window' summarize_claude 4242 /home/wes/Projects/demo.app 1789324406 1 "")
echo "$record" | jq -e '.windowTitle == ""' >/dev/null

# A cwd with spaces and dots maps to Claude Code's folder name.
mkdir -p "$fixture/.claude/projects/-home-wes-My-Projects-demo-app"
printf '%s\n' '{"type":"user","cwd":"/home/wes/My Projects/demo.app","gitBranch":"spaces","message":{"role":"user","content":"x"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t9","name":"Grep","input":{}}]}}' > "$fixture/.claude/projects/-home-wes-My-Projects-demo-app/s2.jsonl"
record=$(summarize_claude 5151 "/home/wes/My Projects/demo.app" 1789324406 1 "")
echo "$record" | jq -e '.branch == "spaces" and .tools == ["Grep"] and .cwd == "/home/wes/My Projects/demo.app"' >/dev/null

# A corrupt session status cannot break the JSON.
cat > "$fixture/.claude/sessions/6161.json" <<'JSON'
{"pid":6161,"sessionId":"abc-123","cwd":"/home/wes/Projects/demo.app","status":"bu\\sy"}
JSON
record=$(summarize_claude 6161 /home/wes/Projects/demo.app 1789324406 1 "")
echo "$record" | jq -e '.sessionStatus | type == "string"' >/dev/null

# No processes match in the fixture, so the full scan prints an empty array.
out=$(AGENTS_SCAN_LIBRARY= AGENTS_SCAN_ONLY="nonexistent-agent-xyz" bash "$here/../scripts/agents-scan.sh")
test "$out" = "[]" || { echo "expected [] from an idle scan, got: $out" >&2; exit 1; }

echo "agents-scan tests passed"
