# Guided tour

- [x] Keep dashboard content at its normal size; tour controls live in an overlay.
- [x] Anchor the spotlight to the real control and scroll it into view per step.
- [x] Dim the surrounding content, block accidental settings changes, and keep
      Back / Next / Skip visible at a fixed location.
- [x] Cover profiles, protection and developer automation with concise steps.
- [x] Verify all steps, Back, Skip, Done, replay, and scrolling in English/Turkish.

The tour is explanatory. It navigates and scrolls but never changes power or
notification preferences. Return advances, Escape skips, and keyboard focus
stays in the tour. The card uses an opaque background for readability. Focus
bounds come from SwiftUI anchors, not fixed control coordinates. Only the
explanation can scroll if it needs more space; navigation stays outside it.

Run `python3 scripts/test-automation.py --tour` after building the Debug app.
The isolated macOS harness checks all eight target positions, pinned navigation
during scrolling, Back / Next / Skip / Done / replay, Return / Escape, and
unchanged settings in English and Turkish. Screenshots are written to
`/private/tmp/battistics-tour-{en,tr}-{0...7}.png` for visual review.
