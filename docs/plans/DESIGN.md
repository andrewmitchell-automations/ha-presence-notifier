# Claude Code Home Assistant Presence Plugin

## Project Overview

A lightweight Claude Code plugin that integrates with Home Assistant to provide automatic presence detection. When Claude Code finishes a response, the plugin queries your Home Assistant person entity to determine if you're home or away. If you're away, it injects a system message prompting Claude to use the push notification tool if it needs your attention or has completed a task.

## Core Concept

- **Stop Hook Integration**: Fires after every Claude response
- **Home Assistant Query**: Checks person entity state via REST API
- **Conditional Continuation**: If away, forces Claude to continue with a system message; if home, exits normally
- **Zero Configuration**: User provides three environment variables and the plugin handles the rest

## Architecture
ha-presence-notifier/
├── README.md
├── SETUP.md
├── manifest.json
├── hooks/
│   └── stop-hook.sh
├── templates/
│   └── settings-template.json
└── example-env.txt

## File Specifications

### manifest.json
Declares the plugin to Claude Code, specifies the hook location, and lists required environment variables.

### stop-hook.sh
Bash script that:
1. Queries Home Assistant API using provided URL and token
2. Checks the specified person entity
3. Returns JSON with `continue: true` and system message if away
4. Returns clean exit if home
5. Handles errors gracefully

### Environment Variables Required
- `HA_URL`: Full URL to Home Assistant instance (e.g., http://localhost:8123 or https://ha.example.com)
- `HA_TOKEN`: Long-lived access token from Home Assistant
- `HA_PERSON_ENTITY`: Person entity ID to query (e.g., person.andrew)

### System Message Prompt
When away, inject: "You are away from home. If you need a decision from the user or are waiting for input, please use the push_notification tool to alert them immediately."

## Implementation Details

### Hook Registration
The plugin should integrate with Claude Code's hook system via the Stop event, configurable in `.claude/settings.json` or `.claude/settings.local.json`.

### Error Handling
- Timeout on Home Assistant API call (default 5 seconds)
- Invalid token or entity: log error, exit cleanly (don't force continuation)
- Network unreachable: exit cleanly (assume home to avoid notification spam)
- Parse failures: exit cleanly with stderr logging

### Push Notification Tool
Assumes Claude Code user has configured the native Claude Code `push_notification` tool. Plugin does not manage tool configuration and does not integrate with any third-party push services (ntfy, Pushover, etc.) — the entire point is to leverage the built-in Claude Code push notification capability.

## Hook Targeting Considerations

The original design targets the **Stop hook**, which fires after every Claude response. This is the broadest coverage but also the noisiest — it triggers a presence check on every message, including ones where Claude is mid-task and not actually waiting on the user.

Worth evaluating during implementation: Claude Code also exposes a dedicated **Notification hook** that fires specifically when Claude needs user attention. It supports matchers including:
- `permission_prompt` — Claude is asking for permission to use a tool
- `idle_prompt` — Claude has been idle waiting for input

These match the exact moments when a push notification is most valuable. Targeting the Notification hook (or both Notification and Stop) may be a cleaner design than Stop alone:

- **Notification hook only**: Most precise — only checks presence when Claude actively needs attention. Doesn't cover the "task complete, FYI" case.
- **Stop hook only**: Covers task completion but checks presence on every message, including chatty back-and-forth where the user is clearly engaged.
- **Both hooks**: Maximum coverage. Notification handles "I'm blocked, please respond"; Stop handles "I finished, you should know." Worth considering whether to use different system messages for each context.

Note: Notification hooks cannot block or modify the notification itself — they're side-effect oriented. But they can still emit a `systemMessage` and `continue` flag the same way Stop hooks can, so the core mechanism (inject context, force continuation, let Claude decide to call the push notification tool) works identically.

## User Setup Flow

1. Clone or install plugin
2. Create Home Assistant long-lived access token
3. Set three environment variables in `.claude/settings.local.json`
4. Plugin is active immediately on next Claude Code session

## Distribution & Customization

- Repo should be public and easily installable
- Include SETUP.md with step-by-step instructions for obtaining HA token
- Include troubleshooting section for common issues
- Allow users to fork and customize system message or entity names

## Future Enhancements

- Support multiple person entities (family members)
- Configurable system message template
- Optional notification cooldown (don't spam if away for extended period)
- Integration with other location services (e.g., other HA-tracked device_trackers, zones beyond just home/away)
