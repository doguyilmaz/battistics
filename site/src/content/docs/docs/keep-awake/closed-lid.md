---
title: Closed-lid mode and the power helper
description: How Battistics keeps a Mac running with its lid shut, and how it gives the setting back.
---

macOS sleeps when the lid closes unless system sleep is turned off, which needs administrator rights. Battistics uses a small helper for that one job.

## Setting it up

The first time you start a closed-lid session, Battistics installs the helper and macOS asks you to allow it in **System Settings › General › Login Items & Extensions**. After that, closed-lid sessions start without a prompt.

## What the helper can do

It can only borrow the sleep setting for a session, change Low Power Mode and the sleep timers you pick in **Power**, and report its version. It never runs a command it was handed.

## Giving the setting back

- The session takes the setting as a 45-second lease that the app renews. If Battistics quits or crashes, the lease runs out and the helper restores sleep.
- If the setting was changed elsewhere during the session, it is left alone.
- When a session ends with the lid shut, the Mac goes to sleep as closing the lid normally would.
- If the helper is stopped or removed, it restores sleep before it exits.

## Repair

After an update, **Power › Power Helper** may say the helper is outdated or not answering. **Repair** replaces it; macOS asks for your password. Repair and Remove are unavailable while a closed-lid session runs.

## Sleep left turned off

If **Power** shows **Sleep is turned off** while no closed-lid session runs, the setting outlived a session, for example after a power loss. Click **Allow Sleep** to turn sleep back on. It also stays off across a restart until you do.
