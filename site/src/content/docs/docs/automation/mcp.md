---
title: MCP for AI clients
description: Let an AI client keep the Mac awake from the start to the end of a task.
---

Battistics bundles a local MCP server. Turn on **Automation › Local automation** and copy the client configuration from that section, or add it yourself:

```json
{"mcpServers": {"battistics": {"command": "/Applications/Battistics.app/Contents/MacOS/battistics-mcp", "args": []}}}
```

## Tools

| Tool | Arguments | Result |
| --- | --- | --- |
| `battistics_status` | None | Battery, current session, protections |
| `battistics_start` | `name`, `duration_minutes` (15–720), optional `mode` | A session ID |
| `battistics_stop` | `session_id` | Status after the session ends |

Have the client call `battistics_start` before work and `battistics_stop` after it, including when the work fails. Each client can only stop the session it started, and only one session runs at a time.

## Safety

The server talks to the app over a private socket for your user only; there is no network port or API key. If the client stalls or exits, its session ends within 45 seconds. MCP cannot change protection settings, fan speeds or other system settings.
