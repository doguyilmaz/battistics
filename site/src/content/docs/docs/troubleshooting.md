---
title: Troubleshooting
description: Fixes for the power helper, iPhone sharing and notifications.
---

## Closed-lid mode does not start

- **Needs approval:** allow Battistics in **System Settings › General › Login Items & Extensions**.
- **Outdated or not answering:** use **Power › Power Helper › Repair**.
- **From the iPhone:** turn on closed-lid sessions in the Mac's **iPhone** pane. The iPhone never installs or repairs the helper; that is done at the Mac.

## The Mac does not sleep any more

Open **Power**. If it shows **Sleep is turned off**, click **Allow Sleep**.

## The iPhone does not find the Mac

- Check that **Show this Mac in Battistics Remote** is on in the Mac's **iPhone** pane.
- Sign in to iCloud with the same Apple Account on both.
- The pane shows an iCloud problem when there is one, such as being signed out or out of storage.

## Nearby connection does not work after an update

Nearby support requires updated versions of both apps; older versions use iCloud. The first trust setup needs successful iCloud access with the same Apple Account, even when both devices are nearby.

- **Bluetooth denied:** on the Mac use **iPhone › Nearby Connections › Bluetooth Privacy Settings**. On the phone use Remote's **Settings › Nearby Connections › Open App Settings**. Enable app access on both devices and return to Remote. Also check that the radio is on; system restrictions may require an administrator.
- **Local Network denied:** allow the app in **Privacy & Security › Local Network** on both devices (macOS 15 or later on the Mac). There is no general permission-status API; a local-network error is shown when the system reports one. An idle search does not prove permission was granted.
- **Same Wi-Fi, still no connection:** guest isolation, multicast filtering or a firewall may prevent discovery. Do not disable the firewall to make the app work; Bluetooth or iCloud can provide another path.
- **Different networks:** local LAN discovery may not work, but Bluetooth can connect nearby devices. For iCloud, both devices need internet. Bluetooth does not give the Mac internet access.

## The Live Activity shows an older update

The timer advances without receiving new readings. Check the last-update time, whether the Mac app is awake and sharing, and available connections. Background App Refresh and Low Power Mode can affect iOS opportunities; even with access enabled, silent pushes may be delayed. Open Remote once to check foreground recovery, but do not treat that as proof of uninterrupted background delivery.

An activity can end after eight hours independently of Keep Awake. Remote does not currently use dedicated ActivityKit push notifications, so another app's **More Frequent Updates** setting would not fix its CloudKit/Bluetooth delivery. See the [iPhone guide](/docs/iphone/).

## No notifications

Allow notifications for Battistics in **System Settings › Notifications**. Keep Awake warnings also show inside the app without permission.

## Something else

Use **Report a Problem** in the popover's settings menu or [open an issue](https://github.com/doguyilmaz/battistics/issues).
