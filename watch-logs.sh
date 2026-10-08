#!/usr/bin/env bash
# Terminal 2: stream OpenShell's security log for the agent's sandbox, live.
# Shows every network decision (ALLOWED/DENIED) and security finding.
until openshell sandbox list 2>/dev/null | grep -q "^triage .*Ready"; do sleep 1; done
openshell logs triage --tail --source sandbox \
  | grep --line-buffered -E "NET:OPEN|NET:REFUSE|HTTP:|FINDING"
