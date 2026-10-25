---
title: Session protection
description: Stops and warnings for battery level, heat and unplugging.
---

Set these in **Power › Session Protection**, or **Stop on Low Battery** in the popover's Keep Awake menu.

- **Battery stop.** Ends the session at 5–50% on battery, 10% when first turned on. Off by default.
- **Low-battery warning.** From 20% by default (10–80%), always at least five points above the stop.
- **Heat.** Serious or critical thermal pressure always warns; stopping on it is optional and works on battery or adapter. Fan speeds are not changed.
- **Adapter unplugged.** An optional warning when the adapter is pulled during a session. It never stops the session.

A stop ends Keep Awake; it never shuts the Mac down or forces sleep. macOS then behaves normally, which with the lid closed means sleeping right away. A stopped session keeps its reason on screen and never restarts by itself.

A closed-lid session started from an iPhone always stops at 10% (or your higher stop) and under heat, since nobody may be at the Mac.

Protection is best effort while the app runs. It cannot warn before a sudden power loss.
