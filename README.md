<p align="center">
  <img src="assets/banner.png" alt="SleepLess — keep your Mac awake, lid open or closed" width="100%">
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-1E1A52">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-3A2668">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-E2624F">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-FFB35A"></a>
</p>

**SleepLess** is a tiny macOS menu-bar app that keeps your Mac awake — with the lid open (optionally dimming the screen) *or* with the lid closed — with sensible safety cut-offs, an auto-off timer, and a helper that can never leave your Mac stuck awake.

<p align="center">
  <img src="assets/menubar-animation.gif" alt="The SleepLess menu-bar icon: rays rise like a sunrise when it turns on, shimmer while it is on, and a sun comes up in lid-closed mode" width="720">
</p>

## Features

- **Keep screen awake** (lid open) — holds the same power assertions as `caffeinate -di`: the screen never idle-dims or sleeps and the Mac never idle-sleeps. No admin rights needed.
- **Screen when idle** — *Stay the same*, or *Dim* to a brightness you choose (0–100 %) after an idle delay (right away, 30 s, 1, 2, 5 or 10 min). Any keyboard or mouse input restores your original brightness instantly; so does turning it off or quitting. It never brightens a screen that is already below the target. The keyboard backlight is left alone.
- **Keep awake with lid closed** — the only thing that beats lid-close sleep on Apple Silicon is the `SleepDisabled` flag (`sudo pmset -a disablesleep 1`). SleepLess sets it through a tiny root helper that you approve once with your password.
- **Safety cut-offs** for lid-closed mode — *Only while charging*, *Pause when running hot* (thermal state serious/critical), a *Low-battery cutoff* slider (default 20 %, 0 = never) and *Automatically enable when charging* (follows plug/unplug).
- **Turn off after** — no limit, 15 min, 30 min, 1, 2 or 4 hours, with a live countdown. When the timer ends everything turns off.
- **Watchdog** — the helper treats a request older than 90 s (app quit, crashed or hung) as "off", so your Mac can never get stuck unable to sleep. Quitting the app restores normal sleep immediately.
- **Animated menu-bar icon** — a rounded "lid" with a horizon line. Turn SleepLess on and rays rise one after another like a sunrise, shimmer gently while it is on, and set again when it turns off. In lid-closed mode a sun rises over the horizon. It is a template image, so it matches light and dark menu bars, and the animation pauses while your screens sleep.
- **Launch at login** (on by default after the first launch) and settings that persist.
- One panel in the menu bar — no Dock icon, no network, no analytics.

## Screenshots

| Light | Dark |
| :---: | :---: |
| <img src="assets/panel-light.png" alt="SleepLess panel, light appearance" width="376"> | <img src="assets/panel-dark.png" alt="SleepLess panel, dark appearance" width="376"> |

## How it works

### Lid open

*Keep screen awake* creates two IOKit power-management assertions — `PreventUserIdleDisplaySleep` and `PreventUserIdleSystemSleep` — exactly what `caffeinate -di` does. They are released the moment you turn it off or quit. Dimming reads and writes the built-in display's brightness through the same private `DisplayServices` calls the brightness keys use, and watches the idle time of the session to restore it on the first key press or mouse move.

### Lid closed

Assertions do not stop a MacBook from sleeping when the lid closes. The only reliable override on Apple Silicon is `SleepDisabled` in `IOPMrootDomain`, which needs root. SleepLess therefore installs a **root launchd helper** — a short shell script, [`sleepless-helper.sh`](sleepless-helper.sh) — with a single macOS admin prompt the first time you flip the switch:

1. The app writes `1` or `0` to `/Library/Application Support/SleepLess/lid` and rewrites it every 30 s while lid-closed mode is on.
2. launchd runs the helper on every write and every 30 s; the helper runs `pmset -a disablesleep 1` or `0` to match.
3. **Watchdog:** a request file older than 90 s counts as `0`. If the app crashes or hangs, normal sleep comes back within about two minutes (90 s of staleness plus up to 30 s until the helper's next run). Quitting normally restores it immediately.
4. The helper only ever undoes a `SleepDisabled` that it set itself (it keeps a marker file), so it will not fight `pmset` or another tool.

The app also reads the live `SleepDisabled` flag, so the panel shows whether lid-closed mode is *really* active, and tells you if something else has disabled sleep.

### Compared with

| | `caffeinate` | [Lidless](https://github.com/nghialuong/Lidless) | SleepLess |
| --- | :---: | :---: | :---: |
| Keep the screen on (lid open) | ✓ | | ✓ |
| Dim the screen while idle | | | ✓ |
| Keep awake, lid closed (`SleepDisabled`) | | ✓ | ✓ |
| Safety cut-offs (charging / thermal / battery) | | ✓ | ✓ |
| Auto-off timer with countdown | `-t` seconds | ✓ | ✓ |
| Watchdog restores sleep if the app dies | n/a | ✓ | ✓ |
| Root helper | none | XPC daemon via `SMAppService` | shell script via launchd, one password prompt |
| Signed & notarized download, auto-updates | | ✓ | build from source |

If you want a mature, feature-rich alternative with a notarized download, [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) is the well-known one.

## Install

Build from source — there are no binary releases. You need Xcode or the Command Line Tools (`xcode-select --install`) on an Apple Silicon Mac running macOS 13 or later.

```bash
git clone https://github.com/CyborgFingers/SleepLess.git
cd SleepLess
./build.sh install   # builds build/SleepLess.app, copies it to /Applications and launches it
```

`./build.sh` on its own just builds `build/SleepLess.app`. The app is ad-hoc signed; because you build it on your own Mac there is no download quarantine and no Gatekeeper prompt.

## First run

- SleepLess lives in the **menu bar** — look for the rounded lid icon. There is no Dock icon.
- It registers itself as a **login item** on first launch (macOS may show a "background items added" notification). Untick *Launch at login* in the panel if you would rather not.
- The first time you turn on **Keep awake with lid closed**, macOS asks for your **administrator password once** to install the helper. You will not be asked again (unless a future version updates the helper, which the app detects and re-installs with one prompt).
- If you use **Bartender**, **Ice** or a similar menu-bar organiser, or your menu bar is crowded next to the notch, the icon may be hidden — look for it there.

## Usage

Click the icon to open the panel.

| Control | What it does |
| --- | --- |
| **Keep screen awake** | Screen stays on and the Mac will not idle-sleep while the lid is open. |
| **When idle** — *Stay the same* / *Dim* | With *Dim*, pick the brightness and the idle delay. Brightness returns on the first key press or mouse move. |
| **Keep awake with lid closed** | Sets `SleepDisabled` through the root helper. The subtitle shows the real state. |
| **Only while charging** | Lid-closed mode turns off (and refuses to turn on) unless the charger is connected. Disables the battery cutoff, since it is no longer needed. |
| **Pause when running hot** | Turns lid-closed mode off while the Mac's thermal state is serious or critical. |
| **Low-battery cutoff** | Turns lid-closed mode off when the battery reaches this level on battery power (default 20 %, 0 = never). |
| **Automatically enable when charging** | Turns lid-closed mode on when you plug in and off when you unplug (after the helper has been installed once). A manual flip sticks until the next plug/unplug. |
| **Turn off after** | Turns *everything* off after 15 min – 4 hours, with a live countdown. |
| **Launch at login** / **Quit** | Quitting releases the assertions, restores brightness and tells the helper to restore normal sleep straight away. |

Whenever a safety guard turns something off, the panel tells you why.

## Safety

- Lid-closed mode is guarded by the thermal, charging and battery rules above, checked every second.
- The root helper's **90 s watchdog** means a crashed, killed or hung SleepLess cannot leave your Mac unable to sleep.
- The helper never touches a `SleepDisabled` it did not set.
- Quitting restores brightness and normal sleep immediately; lid-closed mode is remembered and resumes on the next launch, subject to the same guards.
- Dimming never brightens your screen and always restores exactly the brightness you had.

## Uninstall

```bash
./build.sh uninstall
```

This asks for `sudo` to remove the helper (restoring normal sleep), then removes `/Applications/SleepLess.app`. It removes:

- `/Library/PrivilegedHelperTools/io.github.cyborgfingers.sleepless.lid.sh`
- `/Library/LaunchDaemons/io.github.cyborgfingers.sleepless.lid.plist`
- `/Library/Application Support/SleepLess/`

If SleepLess is still listed under *System Settings → General → Login Items*, untick it there. Settings live in `~/Library/Preferences/io.github.cyborgfingers.sleepless.plist`; `defaults delete io.github.cyborgfingers.sleepless` clears them.

## Testing

```bash
./build.sh && build/SleepLess.app/Contents/MacOS/SleepLess --selftest
```

checks the brightness round-trip (it briefly nudges brightness by 10 %), that both sleep assertions register, and that the battery can be read — handy after a macOS update, since brightness uses a private API.

```bash
./test-helper.sh
```

runs the helper against a fake `pmset` (no root needed) and checks that a fresh request disables sleep, a stale request restores it, a `SleepDisabled` set by someone else is left alone, and a `0` request undoes the helper's own `SleepDisabled`.

## Security & privacy

- **No network, no analytics, no accounts.** Nothing leaves your Mac.
- **Brightness** is read and set through the private `DisplayServices` framework (`DisplayServicesGetBrightness` / `DisplayServicesSetBrightness`). Private APIs can change between macOS releases; `--selftest` tells you if they did.
- **The root helper** is a short, readable shell script. It only ever runs `pmset -g` and `pmset -a disablesleep 0|1`. It is installed by `/bin/sh sleepless-helper.sh install <user>` under a standard macOS admin prompt, and the app checks that the installed copy is byte-for-byte identical to the one in its bundle before trusting it.
- **The request file** (`/Library/Application Support/SleepLess/lid`) is owned by your user in a root-owned directory. Any process running as your user could write `1` to it. The impact is limited to keeping the Mac awake (with the lid closed) while that process keeps rewriting the file, and the 90 s watchdog still applies. The helper reads only the first byte.
- The app is **not sandboxed** (it needs IOKit and the private brightness API) and is ad-hoc signed; you build it yourself.

## Credits

SleepLess was inspired by [Lidless](https://github.com/nghialuong/Lidless) (MIT) — the lid-closed `SleepDisabled` approach, the safety guards, the watchdog idea and the lid-shaped glyph all come from there. SleepLess is an independent implementation with no code or artwork copied, and adds the lid-open, dimming and single-shell-script-helper side.

## License

[MIT](LICENSE) © 2026 CyborgFingers
