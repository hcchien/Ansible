# Current app screens

Screenshots of the **live app** captured on an iOS simulator, for feeding back
into Claude design to fine-tune the Elix style. Each screen is mounted with
seeded zh-Hant data — these are real widgets rendering real layout/color/spacing.

| File | Screen |
| --- | --- |
| `a01_onboarding_welcome.png` | Onboarding A·01 — Welcome / promise |
| `a02_onboarding_promise.png` | Onboarding A·02 — 三條承諾 |
| `b01_timeline_feed.png` | Timeline feed card (Section B) |
| `c01_compose.png` | Post composer |
| `d01_content_detail.png` | Content detail |
| `d02_notifications.png` | Notifications |
| `e01_me_settings.png` | Me / Settings |
| `e15_single_board.png` | Single board — #philosophy (E·15) |

## Design system

These render the **white Threads-style** Elix system: near-white surface,
pure-black text, serif content (`Noto Serif TC` / `Newsreader`) + sans UI
(`Noto Sans TC`), mono labels (`JetBrains Mono`), amber·sage·ember accents.
The fonts are bundled (`assets/fonts/`), so the screenshots match the app's
actual typography.

Relative timestamps (e.g. "13 小時") reflect the simulator's real clock against
the fixed seed times — cosmetic only.

## Regenerate

```bash
cd ansible_node/app
IOS_SIM_ID=<udid> ./scripts/capture_screens.sh
```

The harness lives in `ansible_node/app/integration_test/screens_tour.dart`
(add screens there) and `ansible_node/app/test_driver/screenshot_driver.dart`
(writes the PNGs here).
