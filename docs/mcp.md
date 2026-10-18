# Local MCP automation

Battistics exposes a local stdio MCP server through the bundled
`Battistics.app/Contents/MacOS/battistics-mcp` executable. Open Battistics,
enable **Local MCP automation** in Power, and copy the client configuration
from that section. Automation is off by default. No cloud service, TCP port,
API key, or history access is involved.

## Contract

| Tool | Arguments | Result |
| --- | --- | --- |
| `battistics_status` | None | Battery level/source, current session, protections, closed-lid permission |
| `battistics_start` | `name` (1–80 visible characters), `duration_minutes` (15, 30, 60, 120, 240, 360, 720), optional `mode` (`displayMaySleep`, `displayOn`, `lidClosed`; default `displayMaySleep`) | Session ID and status after activation |
| `battistics_stop` | `session_id` returned by start | Status after releasing this client's session |

Tool results are JSON text. Failures have `isError: true` and a stable `code`
alongside a readable `message`. Codes include `invalid_request`, `unavailable`,
`disabled`, `busy`, `not_owner`, `inactive`, `closed_lid_not_allowed`,
`helper_unavailable`, and `start_failed`. An uncertain start is never retried
automatically. Clients should inspect status before making a new request.

Example start arguments:

```json
{"name":"Build and test my project","duration_minutes":60,"mode":"displayMaySleep"}
```

Call stop when the work finishes, including when it fails or is cancelled.
The server does not infer task completion from the conversation. Each client
owns only the session it started; it cannot replace or stop manual sessions or
another client's session. Only one session runs at a time. The deadline is
absolute and cannot be extended by heartbeats.

## Lifecycle and permissions

The stdio process holds a private Unix socket connection to the app. EOF or
process exit releases its session. A 15-second heartbeat and 45-second lease
also release it if the client stalls (checked every five seconds while the app
can run). User stops, expiry, battery protection,
thermal protection, and disabling automation are final: a heartbeat never
restarts a session. Closed-lid automation needs a separate opt-in and an
already installed power helper; MCP does not install or repair the helper.

The endpoint lives in `/private/tmp/battistics-<uid>/control.sock`, inside an
owner-only directory. Both ends verify the peer's user ID. A file lock prevents
two app copies from taking over the same endpoint. This trusts applications
running as the same macOS user once enabled; it is not a sandbox between AI
clients sharing that user account. Approve only clients you trust.

MCP cannot change protection thresholds, fan speeds, arbitrary system settings,
or request shutdown. Stopping Keep Awake permits normal macOS sleep, including
immediate sleep when the lid is closed.

## Clients

For clients using `mcpServers` (adjust the path for your installation):

```json
{"mcpServers":{"battistics":{"command":"/Applications/Battistics.app/Contents/MacOS/battistics-mcp","args":[]}}}
```

For Codex:

```toml
[mcp_servers.battistics]
command = "/Applications/Battistics.app/Contents/MacOS/battistics-mcp"
```

The implementation uses the [official MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
and its [stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).
Diagnostics belong on stderr; stdout is reserved for MCP messages.

## Verification

`swift test` covers argument validation, lease ownership/deadlines, private
socket permissions and locking, malformed/oversized frames, disconnect during
an asynchronous request, and MCP result serialization. After `make build`,
`python3 scripts/test-mcp-stdio.py` checks the bundled executable's handshake,
tool discovery, schemas, errors, and EOF shutdown without changing power state;
CI runs it too.

On a development Mac, `python3 scripts/test-automation.py` compiles an isolated
test app, exercises real idle/display assertions for a few seconds, and checks
manual/foreign ownership, stale requests, user takeover, disconnect, disable,
and the protection-stop callback. It renders English/Turkish automation views
to `/private/tmp/battistics-automation-{en,tr}.png`. It uses its own preference
domain and temporary endpoint and never installs a helper or enables closed-lid
mode. Physical closed-lid automation still requires a signed-app release check.
