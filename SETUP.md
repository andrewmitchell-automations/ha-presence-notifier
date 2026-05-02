# Setup

## 1. Create a Home Assistant long-lived access token

1. Open Home Assistant in your browser.
2. Click your user avatar (bottom-left) → **Security** tab.
3. Scroll to **Long-lived access tokens** → **Create token**.
4. Give it a name like `claude-code-presence` and copy the token. **You won't see it again.**

## 2. Find your person entity ID

1. In Home Assistant, go to **Developer Tools** → **States**.
2. Filter for `person.`. Note the entity ID (e.g. `person.andrew`).
3. Confirm the `state` column shows `home` when you're home. If you've renamed your home zone, the state will use that name — add it to `HA_PRESENT_STATES`.

## 3. Confirm Claude Code can reach Home Assistant

From the same machine where Claude Code runs:

```sh
curl -fsS -H "Authorization: Bearer $YOUR_TOKEN" \
  "https://ha.example.com/api/states/person.your_name" | jq
```

You should see JSON with `entity_id`, `state`, and `attributes`. If you get a connection error, check:
- Is your HA URL reachable from this machine? (LAN IP vs public hostname)
- If self-hosted with a self-signed cert, you may need `HA_URL` to be the http LAN URL or the Nabu Casa URL rather than a custom https domain
- Is the token correct?

## 4. Install the plugin

In Claude Code:

```
/plugin marketplace add andrewmitchell-automations/ha-presence-notifier
/plugin install ha-presence-notifier@ha-presence-notifier
```

The first command registers this repo as a plugin marketplace; the second installs the plugin from it.

## 5. Configure env vars

Add to `~/.claude/settings.local.json` (or `.claude/settings.local.json` in a project):

```jsonc
{
  "env": {
    "HA_URL": "https://ha.example.com",
    "HA_TOKEN": "<paste-token-here>",
    "HA_PERSON_ENTITY": "person.your_name"
  }
}
```

Restart Claude Code. The hook is active immediately.

## 6. Verify

Trigger any Claude response while you're set to a non-`home` state in HA. You should see Claude call `PushNotification` before stopping. While at home, you should see no behavioral change.

To force away-state for testing, you can temporarily override the state via HA's Developer Tools → States, or temporarily set `HA_PRESENT_STATES=__none__` so nothing matches.

## Troubleshooting

**Nothing happens when away.**
Check Claude Code logs for `ha-presence-notifier:` stderr lines. The hook fails silently on errors but always logs a reason. Common causes:
- `missing required env var` — env vars aren't being inherited by the hook process. Confirm they're in the `env` block of `settings.local.json`, not just your shell profile.
- `Home Assistant query failed` — network/auth issue. Re-run the curl test from step 3.
- `could not parse .state from Home Assistant response` — wrong entity ID, or the response shape is unexpected.

**Push fires every time, including when home.**
Your home zone may not be named `home`. Check the state in HA Developer Tools and set `HA_PRESENT_STATES` accordingly.

**Claude says it pushed but I didn't get a phone notification.**
That's the `PushNotification` tool's behavior, not this plugin's — the tool only pushes to your phone when Remote Control is connected. Without Remote Control, you get a desktop/terminal notification only.
