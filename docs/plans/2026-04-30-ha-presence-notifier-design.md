# HA Presence Notifier — Design (2026-04-30)

Supersedes the open questions in `DESIGN.md`. This doc captures the resolved design.

## Goal

A Claude Code plugin that flips Claude's `PushNotification` calibration from "err toward not sending" to "push proactively" when Home Assistant confirms the user is away from home. Use case: fire a long-running prompt, walk away from the laptop, get a phone push when the response lands.

## Architecture

Three primitives interact:

1. **Stop hook** — fires when Claude is about to stop. The hook script queries Home Assistant, and if the user is away returns a JSON block-decision that forces Claude to continue with an injected `reason`.
2. **Home Assistant REST API** — `GET {HA_URL}/api/states/{HA_PERSON_ENTITY}` with a long-lived bearer token. The `state` field is matched against the configured present-states list.
3. **Built-in `PushNotification` tool** — Claude calls this in the forced continuation. The plugin does not implement push delivery itself; it only nudges Claude to call the tool that ships with Claude Code.

### Why Stop, not Notification

The Notification hook fires *after* Claude Code has already delivered its built-in notification, and Notification hooks are side-effect-only — they cannot return `decision`/`reason` to influence the next turn. Stop is the only hook event that can both (a) intercept the moment Claude finishes a turn and (b) inject context that shapes the next turn.

### Why not UserPromptSubmit

UserPromptSubmit would set awareness up-front but misses the core use case: the user fires a long prompt and *then* leaves. At submit time they were home; only at Stop time (potentially many minutes later) do we know they're away.

## Hook Behavior

On every Stop:

1. If `stop_hook_active` is `true` in the input payload, exit 0 immediately. (Loop guard — we already forced one continuation this prompt; don't loop forever if Claude declined to push.)
2. Query Home Assistant with a 5-second timeout.
3. On any hard failure (network, non-2xx, parse failure, missing state field), exit 0. Fail-closed = assume home; the cost of false silence beats the cost of spurious force-continuations.
4. If the returned `state` is in the present-states list, exit 0.
5. Otherwise output `{"decision": "block", "reason": "<systemMessage>"}` to stdout and exit 0.

### Reason text (the calibration flip)

```
User is confirmed away from home (Home Assistant presence check).
Before stopping, call PushNotification with a one-line summary of
your response — what you accomplished, any blocker hit, or any
decision needed from the user. Keep it under 200 characters.
This overrides your default conservative notification posture;
the away signal is verified.
```

### Presence rules

- `HA_PRESENT_STATES` is a comma-separated list, default `home`.
- Anything outside the list — including `unknown`, `unavailable`, `not_home`, custom zones like `Work` — is treated as away.
- Distinction matters: HA *answered* with an off-list state is a real signal (away). HA *didn't answer* (network/timeout/auth fail) is noise (assume home).

## Configuration

Four env vars, three required:

| Var | Required | Default | Purpose |
|---|---|---|---|
| `HA_URL` | yes | — | Base URL, e.g. `https://ha.example.com` |
| `HA_TOKEN` | yes | — | Long-lived access token |
| `HA_PERSON_ENTITY` | yes | — | e.g. `person.andrew` |
| `HA_PRESENT_STATES` | no | `home` | Comma-separated state names that count as present |

Loaded via Claude Code's settings `env` block (typically `.claude/settings.local.json`) so the user never commits the token.

## Plugin Packaging

Distribute as a real Claude Code plugin (not a hook-script-plus-instructions):

```
ha-presence-notifier/
├── .claude-plugin/
│   └── plugin.json          # plugin manifest, registers Stop hook
├── hooks/
│   └── presence-check.sh    # the actual logic (bash + curl + jq)
├── README.md                # what it does, install + config
├── SETUP.md                 # HA long-lived token walkthrough, troubleshooting
└── LICENSE
```

Installable via `/plugin install <git-url>` or a marketplace entry users can fork.

## Implementation Notes

- Bash + `curl` + `jq`. No other runtime dependencies.
- `curl --max-time 5 -fsS -H "Authorization: Bearer $HA_TOKEN" "$HA_URL/api/states/$HA_PERSON_ENTITY"`.
- Parse with `jq -r .state`. Compare against `HA_PRESENT_STATES` split on `,`.
- All `stderr` logging is informational; never use `set -e` in a way that aborts before the fail-closed exit.
- Output JSON only on the away path; silent exit otherwise (Stop hooks treat empty stdout as "no opinion").

## Out of Scope (v1)

- Multiple person entities / family members
- Notification cooldown
- Custom `reason` template
- Integration with non-HA presence sources (device_tracker, zone proximity, etc.)
- Any third-party push services (ntfy, Pushover, Gotify) — `PushNotification` is the only delivery mechanism

These appear in `DESIGN.md` "Future Enhancements" and stay there.

## Failure Modes (summary table)

| Condition | Behavior | Rationale |
|---|---|---|
| HA reachable, state in present list | Silent exit (no block) | User is home |
| HA reachable, state off list (incl. `unknown`, custom zone) | Block + inject reason | Real away signal |
| HA timeout / network error / 4xx-5xx | Silent exit | Don't spam pushes on infra failures |
| Bad/missing env var | Silent exit, log to stderr | Config error shouldn't break the session |
| `stop_hook_active` true | Silent exit | Loop guard — Claude got one chance |
