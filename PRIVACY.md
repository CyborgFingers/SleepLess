# SleepLess Privacy Policy

_Last updated: 26 September 2026_

SleepLess is developed and published by Weta Technologies Limited ([CyborgFingers on GitHub](https://github.com/CyborgFingers)). In short: **SleepLess collects nothing.**

- No accounts, analytics, tracking, advertising or crash reporting.
- The only network activity is **checking for updates**: SleepLess asks GitHub for its latest release (a standard web
  request, like visiting the releases page — no account, no identifiers, nothing about you or your Mac beyond what any
  web request carries), and downloads an update only when you click **Update Now**. You can turn update checks off in
  the app's settings. Updates are verified with the publisher's update-signing key before they are installed.
- When you first open it, macOS itself may check the app's notarization with Apple. That check is made by macOS, not
  by SleepLess, and is covered by Apple's privacy policy.
- Links you click (for example to GitHub) open in your web browser.
- Nothing is sold, rented or shared — there is nothing to share.

## What stays on your Mac

- Your settings, in `~/Library/Preferences/io.github.cyborgfingers.sleepless.plist` — including, if you set them up, the apps and schedule your automations use and your keyboard shortcut.
- Automations check, on your Mac only, which apps are running, whether it is on the power adapter and whether an external display is connected. Nothing about this is stored or sent.
- `sleepless://` links accept only SleepLess's own commands; nothing is stored or returned.
- If you use lid-closed mode: two small request files (on/off) in `/Library/Application Support/SleepLess/`, read only by SleepLess's own helper.

This data never leaves your Mac. You can delete it at any time (see the README's Uninstall section).

## Permissions SleepLess may ask for

- **Administrator password** — only if you turn on lid-closed mode, to install the helper. You can remove it at any time (see the README's Uninstall section).
- **Notifications** — optional and off until you turn them on; shown on your Mac only.
- **Login item** — so SleepLess starts when you log in; you can turn this off in the app or in System Settings › General › Login Items.

## Children

SleepLess collects no personal information from anyone, including children.

## Changes to this policy

If this policy ever changes, the new version will be published here before the release it applies to and mentioned in
that release's notes.

## Contact

Open an issue at <https://github.com/Weta-Technologies/SleepLess/issues>.
