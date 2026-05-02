# ha-presence-notifier

A Claude Code plugin that flips Claude's `PushNotification` calibration from "err toward not sending" to "push proactively" whenever Home Assistant confirms you're away from home.

## Why

Claude Code's built-in `PushNotification` tool defaults to a conservative posture — it tries hard not to interrupt you. That's the right default when you're at the keyboard. It's the wrong default when you fired off a 20-minute prompt and walked out the door.

This plugin wires a Stop hook to your Home Assistant person entity. When Claude is about to stop and you're verified away, it forces one continuation with an injected instruction to call `PushNotification` before finishing.

## How it works

1. After every Claude response, the Stop hook runs.
2. The hook queries `GET {HA_URL}/api/states/{HA_PERSON_ENTITY}` with your long-lived token.
3. If your `state` is in `HA_PRESENT_STATES` (default: `home`), the hook exits silently and Claude stops normally.
4. Otherwise the hook returns `{"decision": "block", "reason": "..."}`, which forces Claude to continue with an injected instruction to send a `PushNotification` summarizing the response.
5. Claude pushes (or doesn't), then stops. The `stop_hook_active` flag prevents an infinite loop — you only get one forced continuation per prompt.

Any infrastructure failure (network unreachable, bad token, timeout, parse error) makes the hook exit silently — assume home, prefer missed notifications over spurious interruptions.

## Install

In Claude Code:

```
/plugin marketplace add andrewmitchell-automations/ha-presence-notifier
/plugin install ha-presence-notifier@ha-presence-notifier
```

Then set three env vars (see [SETUP.md](./SETUP.md) for details on getting an HA token):

```jsonc
// ~/.claude/settings.local.json
{
  "env": {
    "HA_URL": "https://ha.example.com",
    "HA_TOKEN": "<long-lived-access-token>",
    "HA_PERSON_ENTITY": "person.your_name"
  }
}
```

## Configuration

| Var | Required | Default | Purpose |
|---|---|---|---|
| `HA_URL` | yes | — | Base URL of your Home Assistant instance |
| `HA_TOKEN` | yes | — | Long-lived access token |
| `HA_PERSON_ENTITY` | yes | — | e.g. `person.andrew` |
| `HA_PRESENT_STATES` | no | `home` | Comma-separated state names that count as "present" (e.g. `home,Office` if you've renamed your home zone or want to be considered reachable while at the office) |

Anything outside `HA_PRESENT_STATES` — including `unknown`, `unavailable`, `not_home`, and custom zones like `Work` or `Gym` — is treated as away.

## Requirements

- Claude Code with `PushNotification` available
- A Home Assistant instance reachable from where Claude Code runs
- `bash`, `curl`, and `jq` on `PATH`

## License

MIT
