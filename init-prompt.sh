#!/usr/bin/env bash
set -euo pipefail

# init-prompt.sh — interactively build a PROMPT.md for an AI coding loop

# Helpers
read_nonempty() {
  local prompt="${1:-Enter value}"
  local var
  while true; do
    read -r -p "$prompt: " var || true
    if [[ -n "${var// }" ]]; then
      printf '%s' "$var"
      return 0
    fi
    echo "Please enter a non-empty value."
  done
}

read_optional() {
  local prompt="${1:-Enter value (optional)}"
  local var
  read -r -p "$prompt: " var || true
  printf '%s' "$var"
}

read_multiline() {
  local prompt="${1:-Enter multiple lines}"; shift || true
  local terminator="${1:-END}"
  echo "$prompt (finish with a line containing only '$terminator')"
  local lines=()
  while IFS= read -r line; do
    [[ "$line" == "$terminator" ]] && break
    lines+=("$line")
  done
  printf '%s\n' "${lines[@]}"
}

read_list() {
  local prompt="${1:-Enter item}"; shift || true
  local terminator="${1:-END}"
  echo "$prompt (one per line; finish with '$terminator')"
  local items=()
  while IFS= read -r line; do
    [[ "$line" == "$terminator" ]] && break
    [[ -z "${line// }" ]] && continue
    items+=("$line")
  done
  printf '%s\n' "${items[@]}"
}

iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Gather inputs
echo "=== PROMPT.md Builder ==="
PROJECT_NAME=$(read_nonempty "Project/Feature (one sentence)")
OWNER=$(read_optional "Owner/Stakeholder (optional)")
REPO_ROOT=$(read_optional "Repository root (relative path, optional)")
LANGS=$(read_nonempty "Primary language(s) (e.g., Typescript + React / Ruby / Go)")
RUNTIME=$(read_optional "Runtime & tooling (e.g., node 20, yarn, rails, docker)")
CONSTRAINTS=$(read_optional "Constraints (e.g., must be zero-dependency)")
NONGOALS=$(read_optional "Non-Goals (optional)")

echo
ACCEPTANCE=$(read_list "Acceptance criteria items" "END")

echo
ARCH=$(read_multiline "High-level architecture notes" "END")
ENTRYPOINTS=$(read_multiline "Key entrypoints (file paths / commands)" "END")
TEST_STRAT=$(read_multiline "Test strategy (types & how to run)" "END")
STYLE=$(read_multiline "Coding style (lint/format rules)" "END")

echo
FIRST_SLICE=$(read_optional "First thin slice description (optional, can edit later)")

echo
echo "Runtime commands (optional):"
INSTALL_CMDS=$(read_multiline "Install deps commands" "END")
RUN_CMDS=$(read_multiline "Run app commands" "END")
TEST_CMDS=$(read_multiline "Run tests commands" "END")
LINT_CMDS=$(read_multiline "Lint/format commands" "END")

TIMESTAMP=$(iso_now)

# Build bullet lists
format_list_markdown() {
  # Reads lines from stdin, outputs "- item" bullets (or a single "- N/A")
  local content
  content="$(cat)"
  if [[ -z "${content// }" ]]; then
    echo "- N/A"
  else
    while IFS= read -r line; do
      [[ -z "${line// }" ]] && continue
      echo "- ${line}"
    done <<< "$content"
  fi
}

ACCEPTANCE_MD="$(printf '%s\n' "$ACCEPTANCE" | format_list_markdown)"
ENTRYPOINTS_MD="$(printf '%s\n' "$ENTRYPOINTS" | format_list_markdown)"
INSTALL_MD="$(printf '%s\n' "$INSTALL_CMDS" | format_list_markdown)"
RUN_MD="$(printf '%s\n' "$RUN_CMDS" | format_list_markdown)"
TEST_CMDS_MD="$(printf '%s\n' "$TEST_CMDS" | format_list_markdown)"
LINT_MD="$(printf '%s\n' "$LINT_CMDS" | format_list_markdown)"

# Defaults for TODO section
if [[ -z "${FIRST_SLICE// }" ]]; then
  FIRST_SLICE="Establish scaffolding and test harness"
fi

cat > PROMPT.md <<EOF
# PROJECT BRIEF
A concise, unambiguous description of what we are building.

- Product/Feature: ${PROJECT_NAME}
- Owner/Stakeholder: ${OWNER:-N/A}
- Repository Root: ${REPO_ROOT:-./}
- Primary Language(s): ${LANGS}
- Runtime & Tooling: ${RUNTIME:-N/A}
- Constraints: ${CONSTRAINTS:-N/A}
- Non-Goals: ${NONGOALS:-N/A}

# ACCEPTANCE CRITERIA
${ACCEPTANCE_MD}

# CONTEXT SNAPSHOT (READ-ONLY, MAY BE REFRESHED BY HUMAN)
Provide high-signal notes: domain concepts, existing APIs, file map, links.
- High-level architecture:
${ARCH:-(N/A)}

- Key entrypoints:
${ENTRYPOINTS_MD}

- Test strategy:
${TEST_STRAT:-(N/A)}

- Coding style:
${STYLE:-(N/A)}

---

## AGENT OPERATING PRINCIPLES (DO NOT DELETE)
1. **Small, safe steps.** Prefer the smallest possible diff that advances the goal.
2. **Deterministic output.** Exactly follow the **OUTPUT FORMAT**; never add extra prose outside fenced blocks.
3. **Tests with changes.** When behavior changes, add or update tests in the same iteration.
4. **Idempotency.** Each iteration must be safely re-runnable. If blocked, emit a plan to unblock.
5. **Locality.** Touch the fewest files; keep commits focused and well-titled.
6. **Observability.** Update the STATE block honestly; mark DONE only when acceptance criteria are met.
7. **Security & ethics.** Do not exfiltrate secrets, add network calls, or install global tools without an explicit TODO-Unblock and rationale.
8. **Self-modify only where allowed.** You may update:
   - \`## STATE\` (entire YAML)
   - \`## TODO\` list
   - Append new \`### PATCH n\` blocks
   - Append \`### NEXT_PROMPT_UPDATE\` (which replaces \`## TODO\` and \`## STATE\` on the next run)

---

## TODO
- [ ] Break work into thin vertical slices.
- [ ] First thin slice: ${FIRST_SLICE}
- [ ] Tests needed: Outline the first failing test.
- [ ] Risks/Unknowns: List potential blockers.

---

## STATE
\`\`\`yaml
iteration: 0
timestamp: "${TIMESTAMP}"
status: "planning"  # planning|working|blocked|review|done
current_slice: "${FIRST_SLICE}"
recent_changes: []
open_questions: []
decisions: []
metrics:
  tests_added: 0
  files_changed: 0
  lines_added: 0
  lines_removed: 0
next_actions:
  - "Write first failing test for acceptance criterion #1"
blockers: []
\`\`\`

---

## OUTPUT FORMAT (STRICT)
On each iteration, produce **exactly these fenced blocks** in this order. No extra commentary.

1) A machine-readable **ACTION PLAN** for this iteration (≤3 steps):
\`\`\`action-plan
- Step 1: <tiny step>
- Step 2: <tiny step>
- Step 3: <tiny step>
\`\`\`

2) A unified diff **PATCH** (one or more) applying your changes. Keep each diff ≤ ~150 lines when possible.
Each patch block MUST be a valid \`git diff --unified\` for files in this repo.
\`\`\`patch
*** BEGIN PATCH
*** Update File: path/to/file.ext
@@
- old line
+ new line
*** End Patch
\`\`\`
If creating a file:
\`\`\`patch
*** BEGIN PATCH
*** Add File: path/to/new_file.ext
+<file contents>
*** End Patch
\`\`\`
If no changes this iteration, emit an empty patch block:
\`\`\`patch
*** BEGIN PATCH
*** End Patch
\`\`\`

3) A single-line **COMMIT MESSAGE** (imperative mood):
\`\`\`commit
feat: <short description of what changed>
\`\`\`

4) Any **TEST NOTES** (what tests were added/updated and how to run them):
\`\`\`tests
- Added: path/to/test_file.ext (covers: <behavior>)
- Updated: path/to/existing_test.ext (reason: <reason>)
Run: <command to run tests locally>
\`\`\`

5) Updated **STATE** (YAML). Copy the \`## STATE\` shape and update fields truthfully.
\`\`\`state
iteration: <n>
timestamp: "<ISO8601>"
status: "<planning|working|blocked|review|done>"
current_slice: "<concise>"
recent_changes:
  - "Brief bullet describing what changed"
open_questions: []
decisions: []
metrics:
  tests_added: <int>
  files_changed: <int>
  lines_added: <int>
  lines_removed: <int>
next_actions:
  - "Next minimal step"
blockers: []
\`\`\`

6) **NEXT_PROMPT_UPDATE**: If you want to modify \`## TODO\` and/or \`## STATE\` for the next run, output them here in full. The runner will replace those sections verbatim on the next iteration. If no updates, include empty fenced blocks.
\`\`\`next-prompt-update
## TODO
- [ ] <new or pruned items>
- [ ] <...>

## STATE
\`\`\`yaml
<fully updated YAML to seed next run>
\`\`\`
\`\`\`

7) **DONE** sentinel (optional). Emit only when all acceptance criteria are met and there is genuinely nothing else to do. Otherwise omit.
\`\`\`done
DONE
\`\`\`

---

## RUNTIME COMMANDS (HUMAN-OPERATED, FOR REFERENCE)
- Install deps:
${INSTALL_MD}
- Run app:
${RUN_MD}
- Run tests:
${TEST_CMDS_MD}
- Lint/format:
${LINT_MD}

---

## STYLE NOTES
- Naming: clear, boring, intention-revealing.
- Errors: fail fast, helpful messages.
- Comments: only where they add durable value; otherwise self-documenting code.
- Docs: update README or inline docstrings when behavior changes.

---

## EXAMPLE PLACEHOLDER OUTPUT (FOR FIRST RUN)
\`\`\`action-plan
- Step 1: Create a minimal failing test for the primary behavior.
- Step 2: Implement the smallest slice to make the test pass.
- Step 3: Document commands in README and update TODO.
\`\`\`

\`\`\`patch
*** BEGIN PATCH
*** Add File: README.md
+# ${PROJECT_NAME}
+
+Setup
+\`\`\`
+<HOW TO INSTALL/RUN>
+\`\`\`
+
+Testing
+\`\`\`
+<HOW TO RUN TESTS>
+\`\`\`
*** End Patch
\`\`\`

\`\`\`commit
chore: add initial README with setup and test instructions
\`\`\`

\`\`\`tests
- Added: N/A (next iteration will add first failing test)
Run: <TEST COMMAND>
\`\`\`

\`\`\`state
iteration: 1
timestamp: "${TIMESTAMP}"
status: "planning"
current_slice: "Establish scaffolding and test harness"
recent_changes:
  - "Created README with setup and tests section"
open_questions: []
decisions: []
metrics:
  tests_added: 0
  files_changed: 1
  lines_added: 16
  lines_removed: 0
next_actions:
  - "Add first failing test capturing acceptance criterion #1"
blockers: []
\`\`\`

\`\`\`next-prompt-update
## TODO
- [ ] Add first failing test for Criterion #1.
- [ ] Implement minimal code to pass test.
- [ ] Add CI config for tests.

## STATE
\`\`\`yaml
iteration: 1
timestamp: "${TIMESTAMP}"
status: "planning"
current_slice: "Establish scaffolding and test harness"
recent_changes: []
open_questions: []
decisions: []
metrics:
  tests_added: 0
  files_changed: 0
  lines_added: 0
  lines_removed: 0
next_actions:
  - "Write failing test for Criterion #1"
blockers: []
\`\`\`
\`\`\`

<!-- End PROMPT.md -->
EOF

echo
echo "✅ Wrote PROMPT.md"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "You are in a Git repo. Consider committing PROMPT.md:"
  echo "  git add PROMPT.md && git commit -m 'chore: add PROMPT.md for agent loop'"
fi

echo
echo "Optional loop runner example (edit to your agent CLI):"
cat <<'RUNNER'
while :; do
  cat PROMPT.md | <AGENT_CMD> > .agent.out || true
  # Apply patches from output (requires GNU awk):
  awk '/^\*\*\* BEGIN PATCH/{flag=1;print;next}/^\*\*\* End Patch/{print;flag=0}flag' .agent.out \
    | git apply -p0 --reject --whitespace=fix || true
  # Extract commit message (between ```commit fences):
  msg="$(awk '/^```commit$/{p=1;next}/^```/{if(p){p=0;exit}}p' .agent.out | tr -d '\r')"
  if [ -n "$msg" ]; then git add -A && git commit -m "$msg" || true; fi
  # Exit if DONE sentinel present:
  grep -q '^```done$' .agent.out && break
done
RUNNER
