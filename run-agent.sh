#!/usr/bin/env bash
# Terminal 1: start a sandbox and run the agent in it. Prints the raw system
# prompt, task, model replies and command output, nothing else.
set -euo pipefail
cd "$(dirname "$0")"
REPO="${REPO:-Dreamstick9/openshell-triage-demo}"

# Setup (quiet): image, provider profiles, credentials from .env.
docker build -q -f image/Dockerfile -t triage-agent:local . >/dev/null
openshell provider profile import -f providers/openai.yaml >/dev/null 2>&1 || true
openshell provider profile import -f providers/github.yaml >/dev/null 2>&1 || true
set -a; . ./.env; set +a
openshell provider get openai >/dev/null 2>&1 ||
  openshell provider create --name openai --type openai-triage --from-existing >/dev/null
openshell provider get github >/dev/null 2>&1 ||
  openshell provider create --name github --type github-triage --from-existing >/dev/null

# Fresh sandbox, kept alive so the agent and the log stream can attach to it.
openshell sandbox delete triage >/dev/null 2>&1 || true
openshell sandbox create --name triage --from triage-agent:local \
  --policy policy/triage-policy.yaml --provider openai --provider github \
  -- sleep 3600 >/dev/null 2>&1 &
until openshell sandbox list 2>/dev/null | grep -q "^triage .*Ready"; do sleep 2; done
sleep 5  # let the sandbox apply its provider settings before the agent starts

openshell sandbox exec -n triage -- \
  python3 /usr/local/lib/triage/triage_agent.py \
  "Triage this GitHub issue: https://github.com/$REPO/issues/1"
