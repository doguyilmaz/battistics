# Developer sessions

## `battistics run`

`battistics run [--minutes N] [--name NAME] [--mode MODE] -- COMMAND [ARG...]`

Needs Local automation turned on in the running app. The command runs in your
terminal, not in the app or the helper: same directory, environment and
streams, arguments passed without a shell (use `sh -c` for pipelines). The name
defaults to the command's basename; nothing is recorded.

- Mode defaults to `displayMaySleep`; `lidClosed` needs closed-lid automation
  allowed and the helper installed. Durations: 15, 30, 60, 120, 240, 360 or 720
  minutes, 720 by default.
- A running session is never replaced. If Keep Awake cannot start, the command
  is not launched (exit 69).
- Keep Awake ends when the direct child exits; detached background jobs are not
  tracked. A stop by protection, timeout or lost connection lets the Mac sleep
  but never kills the command.
- Exit status is the child's. A child killed by a signal makes `battistics`
  die from the same signal, so shell loops stop on Ctrl-C. Ctrl-C and hangup
  from the terminal reach the child once; SIGTERM sent to `battistics` is
  forwarded.

## AI tasks

An interactive AI session can sit idle without being finished, so process
lifetime says nothing. Have the client call MCP `battistics_start` before work
and `battistics_stop` after it; see [mcp.md](mcp.md).

## Profiles

AI Focus (2 h), Long Build (4 h), Overnight (12 h), display may sleep, and
Presentation (1 h, display on). They start a finite session, change no
settings, never use closed-lid mode, and do not start over a running session.
