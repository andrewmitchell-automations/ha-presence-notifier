# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Status

This repo is **pre-implementation**. The only artifact is the design spec at `docs/plans/DESIGN.md`. No source files, build system, tests, or commits exist yet. When asked to implement, treat `DESIGN.md` as the source of truth and consult it before writing code.

## What This Project Is

A Claude Code plugin (not a standalone app) that injects presence-awareness into Claude Code sessions by hooking into Home Assistant. When the user is away from home, the plugin uses a hook to instruct the running Claude session to call the built-in `push_notification` tool whenever it needs the user's attention.

The plugin is a tiny shell-script-plus-manifest, distributed as a public repo users clone and configure with three env vars (`HA_URL`, `HA_TOKEN`, `HA_PERSON_ENTITY`).

## Architecture (Big Picture)

The whole design hinges on three Claude Code primitives interacting:

1. **Hooks** — `Stop` and/or `Notification` events fire a shell script. The script's stdout JSON (`{ "continue": true, "systemMessage": "..." }`) is how the plugin steers the next turn.
2. **Home Assistant REST API** — the script polls `/api/states/<person_entity>` with a long-lived bearer token to read `home`/`not_home`.
3. **Built-in `push_notification` tool** — the plugin does *not* implement notifications itself. It only nudges Claude (via `systemMessage`) to call the tool that ships with Claude Code. Do not pull in ntfy, Pushover, or other third-party push services.

### Hook targeting decision

`DESIGN.md` flags this as an open design question, not a settled choice. Three viable shapes:
- **Stop only** — broad but noisy (fires every response).
- **Notification only** — precise (`permission_prompt`, `idle_prompt` matchers) but misses "task done, FYI."
- **Both** — maximum coverage, possibly with different `systemMessage` per context.

When implementing, pick deliberately and document the choice. Notification hooks cannot block the notification itself but can still emit `systemMessage` + `continue`, so the core mechanism works identically in either hook.

### Failure-mode posture

On any error (timeout, bad token, unreachable HA, parse failure) the script must **exit cleanly without forcing continuation**. The default behavior on failure is "assume home" — getting this wrong means notification spam, which is worse than missing a notification. Default HA timeout is 5s.

## Expected Layout (per DESIGN.md)

```
ha-presence-notifier/
├── README.md
├── SETUP.md             # HA long-lived token walkthrough + troubleshooting
├── manifest.json        # plugin declaration, hook registration, env var list
├── hooks/
│   └── stop-hook.sh     # the actual logic
├── templates/
│   └── settings-template.json
└── example-env.txt
```

Implementation language is bash (per the design). Keep it dependency-light — `curl` + `jq` is the expected toolset.

## Conventions Specific to This Repo

- The repo is intended to be public and fork-friendly. Keep the system message and entity-name handling easy to customize without code edits where reasonable.
- The plugin must not manage `push_notification` tool configuration; assume the user has it set up.
- Three env vars are the entire user-facing config surface. Don't grow this without a strong reason.
