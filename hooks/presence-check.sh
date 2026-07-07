#!/usr/bin/env bash
# ha-presence-notifier Stop hook.
#
# Reads Stop-hook JSON on stdin. Queries Home Assistant for the configured
# person entity. If the user's state is outside HA_PRESENT_STATES, blocks the
# Stop and injects a reason instructing Claude to call PushNotification before
# finishing.
#
# Fail-closed on every infrastructure error (network, auth, parse, missing
# config) — silent exit 0 means "no opinion, let Claude stop normally."

set -uo pipefail

log() { printf 'ha-presence-notifier: %s\n' "$1" >&2; }

input=$(cat)

stop_hook_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$stop_hook_active" = "true" ]; then
    exit 0
fi

if [ -z "${HA_URL:-}" ] || [ -z "${HA_TOKEN:-}" ] || [ -z "${HA_PERSON_ENTITY:-}" ]; then
    log "missing required env var (HA_URL, HA_TOKEN, HA_PERSON_ENTITY)"
    exit 0
fi

present_states="${HA_PRESENT_STATES:-home}"

response=$(curl --max-time 5 -fsS \
    -H "Authorization: Bearer $HA_TOKEN" \
    -H "Content-Type: application/json" \
    "${HA_URL%/}/api/states/${HA_PERSON_ENTITY}" 2>/dev/null) || {
    log "Home Assistant query failed (network, timeout, or non-2xx)"
    exit 0
}

state=$(printf '%s' "$response" | jq -r '.state // empty' 2>/dev/null)
if [ -z "$state" ]; then
    log "could not parse .state from Home Assistant response"
    exit 0
fi

IFS=',' read -ra present_array <<<"$present_states"
for present in "${present_array[@]}"; do
    trimmed="${present#"${present%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if [ "$state" = "$trimmed" ]; then
        exit 0
    fi
done

reason="User is confirmed away from home (verified via Home Assistant; presence state: \"${state}\"). If you need a reponse from the user, call PushNotification with a one-line summary of what you need. Keep it under 200 chars. Only call PushNotification if you need action from the user, and if you have not already called PushNotification this turn."

jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
exit 0
