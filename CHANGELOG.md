# Changelog

## Unreleased (0.1.0)

Initial version.

- Menu bar popover with charge and health gauges, capacity, cycles,
  temperature, power, voltage and time estimates
- Customizable menu bar display: bat glyph with live fill, charge, health,
  time, temperature or power text, color rules for low, high and charging
- Dashboard with Overview, History, Details, Peripherals and Energy views
- Charge, power, temperature and health history with day, week, month and
  year charts plus on-battery, charging and fully-charged time totals
- Event driven engine: zero polling while idle, sensors sampled only while
  a window is visible, one coalesced background tick for power history
- Notifications: low battery, drop reminders, charge limit, fully charged,
  high temperature, long time on battery, health decline
- Peripheral battery levels for connected keyboards, mice, trackpads and
  headphones
- Energy view showing the busiest processes, sampled only while open
- CSV export and import of the full history, SQLite storage with automatic
  compaction
- Liquid Glass UI on macOS 26 with native material fallback on macOS 14/15
- Sparkle auto-updates. No analytics, no other network traffic
