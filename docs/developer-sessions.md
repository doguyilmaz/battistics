# Developer sessions

Implementation checklist:

- [x] Optional adapter-disconnect notice during Keep Awake, off by default.
- [x] Bundled `battistics run` command with bounded connection-owned sessions.
- [ ] Finite profiles and a live session card in the Power pane and menu popover.
- [ ] English/Turkish copy, lifecycle tests, app build and UI verification.

## Command contract

`battistics run [--minutes N] [--name NAME] [--mode MODE] -- COMMAND [ARG...]`

Enable local automation in the running Battistics app first. The command uses
the existing local socket and connection ownership; it never executes commands
in the app or privileged helper. It inherits the caller's working directory,
environment and standard streams, and passes arguments directly without shell
evaluation. Use an explicit shell for pipelines. The default name is the command
basename, without its arguments. No command history is stored.

The default mode is `displayMaySleep`, with a 12-hour upper bound. Supported
durations are 15, 30, 60, 120, 240, 360 and 720 minutes. `displayOn` and `lidClosed`
are opt-in modes; closed-lid automation requires existing permission and helper.
An existing session is never replaced. Startup failure means the command is not
launched. After launch, stopping Keep Awake (including protection, timeout or
connection failure) allows normal sleep but does not terminate the command.
The CLI reports this on stderr and never restarts the session automatically.

The direct child exiting releases Keep Awake. Background jobs detached by the
command are not tracked. Child exit status is preserved; signal exits map to
128 + signal. SIGINT, SIGTERM and SIGHUP received by the wrapper are forwarded
to the child. A lost CLI connection releases ownership; the existing 45-second
lease timeout remains a fallback for a hung client.

IPC v1 gains optional `source` (`mcp` or `command`) on start, defaulting to `mcp`
for existing clients. It is a display label, never an authorization boundary.
The public MCP tool schema does not change.

## AI and profiles

An interactive AI process can outlive a task. Use MCP `battistics_start` before
work and `battistics_stop` afterward; an open MCP connection alone does not keep
the Mac awake. The AI client must actually call both tools. A duration is always
required and protection/disconnect rules continue to apply.

Profiles start a finite manual session: AI Focus (2 hours, display may sleep),
Long Build (4 hours, display may sleep), Overnight (12 hours, display may sleep),
and Presentation (1 hour, display on). None changes battery/thermal settings or
enables closed-lid operation. Active sessions must be stopped before a profile
can start. AI Focus is a timer, not AI task detection.

The live card shows the task/profile, origin, actual mode and remaining time,
with an explicit stop action. Command completion is bounded by the timer and
existing protection, just like MCP work.
