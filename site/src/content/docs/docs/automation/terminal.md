---
title: Terminal
description: Keep the Mac awake for exactly as long as a command runs.
---

Turn on **Automation › Local automation** in Battistics. **Copy Terminal setup** copies a line that adds the `battistics` command; paste it into your shell profile (`~/.zshrc`) and open a new Terminal window. Then:

```sh
battistics run --name Build -- swift build
```

```
battistics run [--minutes N] [--name NAME] [--mode MODE] -- COMMAND [ARG...]
```

- The command runs in your terminal, with the same directory, environment and streams. Arguments are passed without a shell; use `sh -c` for pipelines.
- Keep Awake lasts as long as the command, 12 hours at most (`--minutes` takes 15, 30, 60, 120, 240, 360 or 720).
- `--mode` is `displayMaySleep` (default), `displayOn` or `lidClosed`. Closed-lid needs automation allowed for it and the power helper installed.
- A running session is never replaced. If Keep Awake cannot start, the command does not run and `battistics` exits with 69.
- A stop by protection or timeout lets the Mac sleep but never kills the command. The exit status is the command's own.
