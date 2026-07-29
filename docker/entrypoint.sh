#!/usr/bin/env bash
set -euo pipefail

mask() {
  if [[ -n "${1:-}" ]]; then
    printf 'set'
  else
    printf 'unset'
  fi
}

workspace_hint() {
  cat <<'EOF'
[aidp] /workspace is empty.
[aidp] Mount a project with: -v "$(pwd)":/workspace
[aidp] Persist Aidp state with: -v "$(pwd)/.aidp":/workspace/.aidp
EOF
}

print_checklist() {
  printf '[aidp] Provider keys: ANTHROPIC=%s OPENAI=%s GEMINI=%s GOOGLE=%s OPENROUTER=%s\n' \
    "$(mask "${ANTHROPIC_API_KEY:-}")" \
    "$(mask "${OPENAI_API_KEY:-}")" \
    "$(mask "${GEMINI_API_KEY:-}")" \
    "$(mask "${GOOGLE_API_KEY:-}")" \
    "$(mask "${OPENROUTER_API_KEY:-}")"

  printf '[aidp] GitHub access: GH_TOKEN=%s GITHUB_TOKEN=%s gh=%s\n' \
    "$(mask "${GH_TOKEN:-}")" \
    "$(mask "${GITHUB_TOKEN:-}")" \
    "$(command -v gh >/dev/null 2>&1 && printf 'installed' || printf 'missing')"
}

print_checklist

if [[ -d /workspace ]] && [[ -z "$(find /workspace -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  workspace_hint
fi

if [[ $# -eq 0 ]]; then
  if [[ ! -t 0 || ! -t 1 ]]; then
    echo "[aidp] Interactive mode works best with -it." >&2
  fi
  cd /opt/aidp
  exec bundle exec aidp
fi

if [[ "$1" == "aidp" ]]; then
  shift
fi

if [[ $# -eq 0 ]] && [[ ! -t 0 || ! -t 1 ]]; then
  echo "[aidp] Interactive mode works best with -it." >&2
fi

cd /opt/aidp
exec bundle exec aidp "$@"
