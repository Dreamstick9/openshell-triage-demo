#!/usr/bin/env bash
# Least-privilege approval: the agent needs to post ONE comment. It asks for
# exactly that, a human reviews OpenShell's risk check, and only that path opens.
set -euo pipefail
cd "$(dirname "$0")"

REPO="${REPO:-Dreamstick9/openshell-triage-demo}"
SANDBOX=approval
run() { openshell sandbox exec -n "$SANDBOX" --no-tty --timeout 120 -- sh -c "$1" </dev/null; }
post_comment() {
  run "curl -s -o /dev/null -w 'POST issue #$1 comment -> HTTP %{http_code}\n' -X POST \
    -H \"Authorization: Bearer \$GITHUB_TOKEN\" \
    -d '{\"body\":\"Triage summary: /login 500 after v2.14.0. Needs backend logs. (posted by the sandboxed agent after a human-approved policy change)\"}' \
    https://api.github.com/repos/$REPO/issues/$1/comments"
}

echo "==> Starting a sandbox with the same least-privilege policy"
openshell sandbox delete "$SANDBOX" >/dev/null 2>&1 || true
openshell sandbox create --name "$SANDBOX" --from triage-agent:local \
  --policy policy/triage-policy.yaml --provider openai --provider github -- sleep 3000 >/dev/null 2>&1 &
until openshell sandbox list 2>/dev/null | grep -q "^$SANDBOX .*Ready"; do sleep 3; done
openshell settings set "$SANDBOX" --key agent_policy_proposals_enabled --value true --yes >/dev/null
# The setting reaches the sandbox on its next settings poll; wait for the
# policy advisor API to answer before using it.
until run "curl -s -o /dev/null -w '%{http_code}' http://policy.local/v1/policy/current" | grep -q 200; do sleep 3; done

echo; echo "==> 1. The task needs one write. GitHub is read-only, so it is blocked:"
post_comment 1

echo; echo "==> 2. The sandbox proposes the narrowest rule that would allow it:"
sed "s#Dreamstick9/openshell-triage-demo#$REPO#" docs/comment-proposal.json > /tmp/proposal.json
CHUNK=$(openshell sandbox exec -n "$SANDBOX" --no-tty --timeout 60 -- \
  sh -c "curl -s -X POST http://policy.local/v1/proposals -H 'Content-Type: application/json' --data-binary @-" \
  < /tmp/proposal.json | jq -r '.accepted_chunk_ids[0]')
echo "proposal $CHUNK submitted"

echo; echo "==> 3. A human reviews it, including the prover's risk finding:"
openshell rule get "$SANDBOX" --status pending

read -r -p "Approve this rule? [y/N] " answer
if [[ "$answer" != [yY] ]]; then
  openshell rule reject "$SANDBOX" --chunk-id "$CHUNK" --reason "not needed for triage"
  exit 0
fi
openshell rule approve "$SANDBOX" --chunk-id "$CHUNK"

echo; echo "==> 4. Wait until the sandbox has loaded the new rule (no restart):"
run "curl -s 'http://policy.local/v1/proposals/$CHUNK/wait?timeout=120'" \
  | jq -r '"status: \(.status), policy_reloaded: \(.policy_reloaded)"'

echo; echo "==> 5. The approved action now works:"
post_comment 1

echo; echo "==> 6. Anything wider is still blocked:"
post_comment 2
