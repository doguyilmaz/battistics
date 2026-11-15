---
title: Install
description: Download the DMG or install with Homebrew.
---

## Download

Download the latest DMG from the [download button](/#download) or from [GitHub Releases](https://github.com/doguyilmaz/battistics/releases/latest), open it and drag **Battistics** to **Applications**.

## Homebrew

```sh
brew install --cask doguyilmaz/tap/battistics
```

## Updates

Battistics updates itself. When an update is found in the background it shows in the menu bar panel and, if notifications are allowed, as a notification. **Check for Updates** is in the popover's settings menu. Homebrew is told to leave an installed copy alone, so the two never fight over versions.

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon
- A MacBook for the battery readings; on a desktop Mac the app still reports accessories and keeps the Mac awake.

## Optional permissions

The app requests permissions when the related feature is used, rather than asking for everything during installation. Bluetooth supports accessory readings and nearby iPhone sharing. The next update also uses Local Network for nearby sharing. Location on the Mac is optional for the Wi-Fi/Hotspot name; notifications are optional for alerts. Closed-lid sessions require the separately approved power helper.

If a request was denied, change it later in **System Settings › Privacy & Security**. The Mac's **iPhone** pane and Remote's **Settings › Nearby Connections** explain the nearby permissions. iCloud sharing still requires the same Apple Account and internet for initial setup. See [the iPhone guide](/docs/iphone/).

## Uninstall

Quit Battistics, then move it from Applications to the Trash. If you used closed-lid Keep Awake, first remove the power helper in **Power › Power Helper › Remove Helper**.
