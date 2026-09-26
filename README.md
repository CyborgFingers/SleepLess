<p align="center">
  <img src="assets/banner.png" alt="SleepLess — keep your Mac awake, lid open or closed" width="100%">
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-1E1A52">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-3A2668">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-E2624F">
  <a href="https://github.com/Weta-Technologies/SleepLess/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Weta-Technologies/SleepLess?color=3A2668&label=release"></a>
  <a href="LICENSE"><img alt="Freeware, all rights reserved" src="https://img.shields.io/badge/license-freeware%20%C2%B7%20all%20rights%20reserved-FFB35A"></a>
</p>

<p align="center">
  <a href="https://github.com/Weta-Technologies/SleepLess/releases/latest/download/SleepLess.pkg"><img alt="Download SleepLess for Mac" src="https://img.shields.io/github/v/release/Weta-Technologies/SleepLess?style=for-the-badge&label=Download%20for%20Mac&color=E2624F"></a>
  <br>
  <sub>macOS 13+ · Apple Silicon · free · Weta Technologies Limited · GitHub: <a href="https://github.com/CyborgFingers">CyborgFingers</a></sub>
</p>

**SleepLess** is a tiny macOS menu-bar app that keeps your Mac awake — with the lid open (screen on, dimmed, or allowed to sleep) *or* with the lid closed — with sensible safety cut-offs, a timer that ends after a duration or at a time, automations that keep it awake while an app runs, on power, with a display or on a schedule, a keyboard shortcut, a URL scheme for Shortcuts and scripts, and a helper that can never leave your Mac stuck awake.

<p align="center">
  <img src="assets/menubar-animation.gif" alt="The SleepLess menu-bar icon, a screen with a sunrise inside: a hollow sun at the bottom when off; the sun rises and five rays fan out when it turns on; the sun lifts into the middle of the screen in lid-closed mode" width="720">
</p>

## Features

- **Keep awake** (lid open) — holds the same power assertions as `caffeinate -di`: the screen never idle-dims or sleeps and the Mac never idle-sleeps. No admin rights needed.
- **When idle** — *Stay on*; *Dim* to a brightness you choose (0–100 %) after an idle delay (right away, 30 s, 1, 2, 5 or 10 min), with any keyboard or mouse input restoring your original brightness instantly (it never brightens a screen that is already below the target, and leaves the keyboard backlight alone); or *Sleep* — the screen sleeps as usual while the Mac stays awake (the system half of the assertions alone, like `caffeinate -i`), for overnight downloads, renders and builds.
- **Keep awake with lid closed** — the only thing that beats lid-close sleep on Apple Silicon is the `SleepDisabled` flag (`sudo pmset -a disablesleep 1`). SleepLess sets it through a tiny root helper that you set up once — one macOS prompt, your password or Touch ID — and that afterwards updates itself only from files signed by Weta Technologies, so nothing ever asks again. Close the lid and the screen and keyboard backlight go dark while everything keeps running; open it and you're right where you left off — no unlock needed.
- **Charging light off when closed** — in lid-closed mode, closing the lid switches the MagSafe connector's light off (handy in a dark bedroom); opening it gives the light back to macOS in the right colour. On by default; a switch under *Safety* turns it off.
- **Safety cut-offs** for lid-closed mode, tucked under a *Safety* disclosure with a one-line summary — *Only while charging*, *Pause when running hot* (thermal state serious/critical), a *Low-battery cutoff* slider (default 20 %, 0 = never) and *Turn on when charging* (follows plug/unplug).
- **Turn off** — never, in 15 min, 30 min, 1, 2 or 4 hours, or *at a time* you pick (today if it is still ahead, otherwise tomorrow — DST-safe). The status header counts down, a progress bar runs under the timer, and *Time left in the menu bar* puts the remaining time (1h 12m) beside the icon. When the timer ends everything you switched on turns off; automations keep their own hours.
- **Automations** — keep the Mac awake by itself *while an app is running* (pick from the apps running now, or any app — a call, a presentation, a build, an export), *on the power adapter*, *with an external display*, or *on a schedule* (days of the week and a window; an end time earlier than the start runs overnight, 0:00 – 0:00 is all day). All off by default, collapsed behind a one-line summary that says which rule is holding right now, and the status header spells it out (*While FaceTime is running*). A click on the icon pauses an automation until its reason ends. Event-driven — app launches and quits, displays coming and going — no polling, no permissions.
- **One click on, one click off** — a quick click on the menu-bar icon turns SleepLess on (bringing back the modes you last had on; screen awake by default) or off. Press and hold the icon for the settings panel; right-click (or ⌃-click) it for the **quick menu**: what SleepLess is doing, Turn On/Off, *Keep awake for* 15 min – 4 hours / *Until a time…* / *Indefinitely*, Settings… and Quit.
- **Keyboard shortcut** — record any ⌘, ⌃ or ⌥ combination (or a function key) and it does what a click on the icon does, from any app. A system hot key, so no Accessibility permission.
- **Notifications** — optional: when a timer ends, or a safety rule turns lid-closed mode off. macOS asks for permission only when you turn it on.
- **Shortcuts & scripts** — `open "sleepless://on?minutes=30"`, `sleepless://on?until=17:30`, `sleepless://on`, `sleepless://off`, `sleepless://toggle`, `sleepless://lid?on=1` — from the Shortcuts app (*Open URLs*), another app or a shell. Only those verbs and parameters are accepted; values are clamped and anything else is dropped.
- **Watchdog** — the helper treats a request older than 90 s (app quit, crashed or hung) as "off", so your Mac can never get stuck unable to sleep. Quitting the app restores normal sleep immediately.
- **Animated menu-bar icon** — a screen with the app icon's sunrise inside. Off is a hollow sun resting on the bottom of the screen. Turn SleepLess on and the sun climbs in and five rays fan out one after another; they breathe slowly while it is on, and it all sets again when it turns off. In lid-closed mode the sun lifts to the middle of the screen as a full disc. It is a template image, so it matches light and dark menu bars; the animation pauses while your screens sleep, and under Reduce Motion it simply switches between still frames.
- **Launch at login** (on by default after the first launch) and settings that persist — and survive updates: a new version never resets them.
- **Updates itself** — checks GitHub about once a day (you can turn that off), shows an *Update available* card in the panel and a dot on the icon, and **Update Now** installs the signed update and relaunches with your settings intact. [Details below.](#updates)
- One panel in the menu bar with a live status header (mode · time left · which automation is holding), a card per mode, the timer, and *Automations* and *More* tucked behind one-line summaries; tooltips on everything and full VoiceOver and keyboard support; it respects Reduce Motion and Increase Contrast. No Dock icon, no analytics, no network beyond the update check.

## Screenshots

| Light | Dark |
| :---: | :---: |
| <img src="assets/panel-light.png" alt="SleepLess panel, light appearance" width="344"> | <img src="assets/panel-dark.png" alt="SleepLess panel, dark appearance" width="344"> |
| <img src="assets/automations-light.png" alt="The Automations section expanded, light appearance" width="344"> | <img src="assets/automations-dark.png" alt="The Automations section expanded, dark appearance" width="344"> |

<p align="center"><img src="assets/menu-light.png" alt="The right-click menu on the menu-bar icon: the current state, Turn On, Keep awake for 15 minutes to 4 hours, Until a time, Indefinitely, Settings and Quit" width="464"><br><sub>Right-click (or ⌃-click) the icon for the quick menu.</sub></p>

## How it works

### Lid open

*Keep awake* creates two IOKit power-management assertions — `PreventUserIdleDisplaySleep` and `PreventUserIdleSystemSleep` — exactly what `caffeinate -di` does (with *Sleep* chosen for the idle screen, only the second one, like `caffeinate -i`). Automations hold the same assertions while their rule is true. They are released the moment you turn it off or quit. Dimming reads and writes the built-in display's brightness through the same private `DisplayServices` calls the brightness keys use, and watches the idle time of the session to restore it on the first key press or mouse move.

### Lid closed

Assertions do not stop a MacBook from sleeping when the lid closes. The only reliable override on Apple Silicon is `SleepDisabled` in `IOPMrootDomain`, which needs root. SleepLess therefore installs a **root launchd helper** — a short shell script, [`sleepless-helper.sh`](sleepless-helper.sh). The Installer package does it under its own admin prompt, so the helper is there before the menu-bar icon first appears; a copy built from source gets the panel's one-time setup card (or the *Set up…* button on this card) instead — either way a single macOS authorization prompt, your password or Touch ID, installs everything SleepLess will ever need as root. From then on nothing asks again — a new version's helper files are installed by the helper itself, and only when they carry a manifest signed with the Weta Technologies publisher key (see [Updates](#updates)):

1. The app writes `1` or `0` to `/Library/Application Support/SleepLess/lid` and rewrites it every 30 s while lid-closed mode is on.
2. launchd runs the helper on every write and every 30 s; the helper runs `pmset -a disablesleep 1` or `0` to match.
3. **Watchdog:** a request file older than 90 s counts as `0`. If the app crashes or hangs, normal sleep comes back within about two minutes (90 s of staleness plus up to 30 s until the helper's next run). Quitting normally restores it immediately.
4. The helper only ever undoes a `SleepDisabled` that it set itself (it keeps a marker file), so it will not fight `pmset` or another tool.
5. **Charging light:** the app writes `off` (lid closed) or `on` (lid open) to `/Library/Application Support/SleepLess/led`; the helper passes only those two words to a tiny tool, [`sleepless-led`](sleepless-led.c), which writes the one SMC key that picks the MagSafe light's colour (`off` = light off; `on` = the colour macOS would show right now, then back to macOS). Each request is applied once, and the watchdog also restores the light if the app dies with it off.

**Dark screen, Mac on, no unlock.** With the lid shut, SleepLess doesn't leave the display lit: it watches the lid sensor (`AppleClamshellState`), and once the lid is closed — with no external monitor connected — it saves your screen and keyboard-backlight levels and turns both down to 0 (pausing the keyboard's ambient-light adjustment). It deliberately does *not* put the display to sleep: a sleeping display trips macOS's "require password" lock, a dark one doesn't. So the Mac stays fully awake, apps, downloads and agents keep running, and when you open the lid your levels come back and you're straight back in your session. With a monitor plugged in it's ordinary clamshell use, and SleepLess leaves the screens alone.

> **Heads-up:** because the screen never "turns off", opening the lid doesn't ask for your password. If you want it locked, press ⌃⌘Q before you close the lid (it keeps running either way).

The app also reads the live `SleepDisabled` flag, so the panel shows whether lid-closed mode is *really* active, and tells you if something else has disabled sleep.

## Install

### Download (easiest)

1. **[Download SleepLess.pkg](https://github.com/Weta-Technologies/SleepLess/releases/latest/download/SleepLess.pkg)** — always the latest release ([all releases](https://github.com/Weta-Technologies/SleepLess/releases)).
2. Open it: **Continue**, **Agree** to the licence, **Install**. macOS asks for your password or Touch ID **once**: that puts SleepLess into Applications and sets up its helper, and SleepLess opens in your menu bar with lid-closed mode ready. Nothing asks again — not the app, and not later updates.

   The package and the app are Developer ID signed and notarized by Apple (the official builds are signed and notarized by Weta Technologies Limited — see [SECURITY.md](SECURITY.md) for how to check a download), so there is no Gatekeeper step and the app opens without a warning. Requires an Apple Silicon Mac running macOS 13 or later. Running the package again over an installed SleepLess (or a newer one) simply upgrades it; your settings are kept. (The 1.0 release was an unsigned drag-to-Applications DMG: if you still have that one, macOS 15 and later make you allow it under *System Settings → Privacy & Security → Open Anyway* — the package replaces it, and does not.)

### Build from source

You need Xcode or the Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/Weta-Technologies/SleepLess.git
cd SleepLess
./build.sh install   # builds build/SleepLess.app, copies it to /Applications and launches it
```

`./build.sh` on its own just builds `build/SleepLess.app`. The app is ad-hoc signed; because you build it on your own Mac there is no download quarantine and no Gatekeeper prompt. `./make-pkg.sh` builds the Installer package (`build/SleepLess.pkg`) that is attached to each release: the app, the licence pane, and pre/post-install scripts ([`pkg/`](pkg/)) that quit a running copy properly, hand the app to the logged-in user, install the helper for them and open the app.

## First run

- SleepLess lives in the **menu bar** — look for the small screen-with-a-sunrise icon. There is no Dock icon. **Click** the icon to turn SleepLess on or off; **press and hold** it for the settings panel; **right-click** (or ⌃-click) it for the quick menu. The panel shows this tip once.
- It registers itself as a **login item** on first launch (macOS may show a "background items added" notification). Untick *Launch at login* in the panel if you would rather not.
- Installed with the package, the helper behind lid-closed mode and the charging light is already set up — the installer's prompt was the one. Built from source, the panel opens with a **one-time setup** card instead: **Set up now** brings one macOS prompt — your password, or Touch ID on Macs that have it — and nothing asks again; **Later** leaves those two features off, each with its own *Set up…* button, until you are ready. (A *Reinstall helper…* link under *Safety* is there if the helper is ever removed.)
- If you use a menu-bar organiser app, or your menu bar is crowded next to the notch, the icon may be hidden — look for it there.

## Usage

A **quick click** on the menu-bar icon turns SleepLess on or off: on brings back whatever modes you last had on (screen awake the first time), off turns everything off — and pauses any automation that is holding, until its reason ends. **Press and hold** the icon to open the settings panel; Esc, another click on the icon, or a click anywhere else closes it. **Right-click** (or **⌃-click**) the icon for the quick menu: the current state, Turn On/Off, *Keep awake for* 15 minutes to 4 hours, *Until a time…* (opens the panel with the time picker), *Indefinitely*, Settings… (⌘,) and Quit (⌘Q). The keyboard shortcut you record under *More* is another click on the icon.

| Control | What it does |
| --- | --- |
| **Status header** | The big glyph and sentence say what SleepLess is doing right now — the mode, the time left, and which automation is holding (*Screen stays on · 1:12:05 left · while FaceTime is running*); its switch is the same on/off as a click on the menu-bar icon. |
| **Keep awake** | The Mac will not idle-sleep while the lid is open; what the screen does is the next row. |
| **When idle** — *Stay on* / *Dim* / *Sleep* (shown while the mode is on) | *Stay on*: the screen never dims or sleeps. *Dim*: pick the brightness (*Dim to*) and the idle delay (*After*); brightness returns on the first key press or mouse move. *Sleep*: the screen sleeps as usual, the Mac stays awake. |
| **Keep awake with lid closed** | Sets `SleepDisabled` through the root helper. Closing the lid turns the screen and keyboard light down to off while the Mac keeps running, without locking. The subtitle shows the real state. |
| **Safety** (disclosure, with a summary like *Stops at 20 % · Pauses when hot* and the battery level) | The rules below. |
| **Only while charging** | Lid-closed mode turns off (and refuses to turn on) unless the charger is connected. Disables the battery cutoff, since it is no longer needed. |
| **Pause when running hot** | Turns lid-closed mode off while the Mac's thermal state is serious or critical. |
| **Low-battery cutoff** | Turns lid-closed mode off when the battery reaches this level on battery power (default 20 %, 0 = never). |
| **Turn on when charging** | Turns lid-closed mode on when you plug in and off when you unplug (after the helper has been installed once). A manual flip sticks until the next plug/unplug. |
| **Turn off** | *Never*, *In 15 minutes* – *In 4 hours*, or *At a time* (a time picker appears; today if still ahead, else tomorrow): turns everything you switched on off, with the countdown in the status header and a progress bar. Picking again restarts the countdown. *Time left in the menu bar* shows the remaining time (1h 12m) beside the icon. |
| **Automations** (disclosure, with a summary like *FaceTime, Keynote · Weekdays 9:00 AM – 5:00 PM*, or the rule holding right now) | *While an app is running* — a list of apps with an *Add app* menu of the apps running now (or *Other…* for any app). *On the power adapter*. *With an external display*. *On a schedule* — day buttons and *From* / *to* times (an end at or before the start runs overnight). Each row says when it is keeping the Mac awake, or paused by a click. |
| **More** (disclosure) | *Keyboard shortcut* — click *Record shortcut*, press the keys (⌘, ⌃ or ⌥ plus a key, or a function key), Esc cancels, × removes it. *Notify me* — when a timer ends or a safety rule turns lid-closed mode off (macOS asks for permission then). *Shortcuts & scripts* — the `sleepless://` commands. |
| **Launch at login** / **Quit** | Quitting releases the assertions, restores brightness and tells the helper to restore normal sleep straight away. |

Every control has a tooltip, everything works with the keyboard and VoiceOver, and the panel respects Reduce Motion (no shimmer, no transitions) and Increase Contrast.

Whenever a safety guard turns something off, the panel tells you why.

## Updates

SleepLess checks GitHub for a newer release about 10 seconds after launch and then once a day — one plain request to `api.github.com` for the latest release, with no account and nothing about you or your Mac — and whenever you click **Check for Updates** in the panel. Untick **Check for updates automatically** to stop the daily check (the button still works). When there is one, the panel shows an *Update available* card with the version, the first lines of the release notes and a *What's new…* link, and a small dot appears on the menu-bar icon (macOS may also show a notification, if you allow SleepLess notifications).

**Update Now** downloads `SleepLess.app.zip` from the release and checks its **Ed25519 signature** against the Weta Technologies publisher key built into the app — a download that doesn't verify is never unpacked. It then unpacks the zip beside the app, checks that the new bundle really is SleepLess at the advertised, newer version with a valid code signature, and hands over to a tiny script that waits for SleepLess to quit, swaps the two bundles with two renames (the old one is put back if anything fails) and relaunches. SleepLess quits normally, so brightness, the keyboard light and the charging light are handed back first. It all takes a couple of seconds. **Later** hides the card until the next check; **Skip** ignores that version.

Your settings live outside the app (`~/Library/Preferences/io.github.cyborgfingers.sleepless.plist`), so they survive, and so does *Launch at login*. If the update changes the helper, the installed helper takes the new files by itself: they come with a manifest signed with the same publisher key, which the root-owned helper verifies (signature, every file's hash, no downgrade) before installing anything, so there is no new prompt. If SleepLess can't replace itself where it is — in a folder you can't write to, say — the card says so and offers the download page instead (the package installs over the old version too).

## Safety

- Lid-closed mode is guarded by the thermal, charging and battery rules above, checked every second.
- The root helper's **90 s watchdog** means a crashed, killed or hung SleepLess cannot leave your Mac unable to sleep.
- The helper never touches a `SleepDisabled` it did not set.
- Quitting restores brightness and normal sleep immediately; lid-closed mode is remembered and resumes on the next launch, subject to the same guards.
- Dimming never brightens your screen and always restores exactly the brightness you had.

## Uninstall

Quit SleepLess, then remove the helper (this restores normal sleep) and, if you installed with the package, its receipt:

```bash
sudo /bin/sh /Applications/SleepLess.app/Contents/Resources/sleepless-helper.sh uninstall
sudo pkgutil --forget io.github.cyborgfingers.sleepless.pkg
```

and move `/Applications/SleepLess.app` to the Trash. If you built from source, `./build.sh uninstall` does all of it. The helper's files are:

- `/Library/PrivilegedHelperTools/io.github.cyborgfingers.sleepless.lid.sh` (and `.led`, `.verify`, `.pub`, `.manifest` beside it)
- `/Library/LaunchDaemons/io.github.cyborgfingers.sleepless.lid.plist`
- `/Library/Application Support/SleepLess/`

If SleepLess is still listed under *System Settings → General → Login Items*, untick it there. Settings (and the modes a click brings back) live in `~/Library/Preferences/io.github.cyborgfingers.sleepless.plist`; `defaults delete io.github.cyborgfingers.sleepless` clears them.

## Testing

```bash
./build.sh && build/SleepLess.app/Contents/MacOS/SleepLess --selftest
```

is side-effect-free — it reads (brightness, battery) but changes nothing on the Mac — and checks the menu-bar click logic (tap / hold / right-click, and what a tap turns on and off); the updater's pure parts — version ordering (1.10 > 1.9, tags with and without `v`, pre-releases ignored), the release-feed parser, Ed25519 verification with a throwaway key pair (good, tampered, wrong key), and the bundle-swap script on a fake app in a temp folder (a success, and a failure that must put the old app back); settings migration (a blob exactly as 1.2.1 wrote it keeps every value and takes defaults for the new fields; empty, wrong-typed and newer blobs never reset anything); the timer clock (*at a time* today vs tomorrow, and a DST change that must not add or drop an hour); schedule windows (day boundaries, overnight, all day, a DST day); automations (overlapping reasons in order, the status sentence); the URL scheme against thirty hostile inputs; and the shortcut labels.

```bash
build/SleepLess.app/Contents/MacOS/SleepLess --selftest-hardware
```

is the one that **touches the Mac** for about a second — it nudges the screen brightness by 10 % and back, turns the keyboard backlight off and back, and holds the sleep assertions for an instant — to prove the private brightness API and the assertions still work after a macOS update. Run it by hand, never from a script.

```bash
./test-helper.sh
```

runs the helper against a fake `pmset` and a fake light tool (no root needed) and checks that a fresh request disables sleep, a stale request restores it, a `SleepDisabled` set by someone else is left alone, a `0` request undoes the helper's own `SleepDisabled`, only `off`/`on` ever reach the light tool, and — with throwaway keys and a fake app bundle — that a signed helper update is installed exactly once, while a file changed after signing, a manifest signed with another key, a downgrade, an unsigned bundle, a symlinked request and a request that isn't an app path all leave the installed helper untouched.

```bash
./test-update.sh
```

runs the in-app updater end to end without GitHub: it serves a fake latest-release feed and a signed zip of this build re-versioned as 9.9.9 from a local web server, then runs a *copy* of the app from a temp folder with `--update-test <feed> <key> <log>`, which does exactly what Update Now does — check, download, verify, unpack, sanity-check, swap, relaunch — and proves the copy comes back as 9.9.9 with nothing left behind, that a zip signed with the wrong key and a tampered zip are refused with the copy untouched, and that your real settings never change. Your installed SleepLess is not involved.

## Security & privacy

- **No analytics, no accounts.** The only network activity is the [update check](#updates) — a plain request to GitHub for the latest release, about once a day, which you can turn off — and the download you start with Update Now. Nothing about you or your Mac is sent.
- **Updates are signed.** Every release's `SleepLess.app.zip` carries an Ed25519 signature made with the Weta Technologies publisher key; the app verifies it with the public key compiled in ([`cyborgfingers.pub`](cyborgfingers.pub)) before unpacking, then checks the bundle id, version and code signature of what it unpacked. Nothing from a download ever runs except that verified app.
- **Brightness** is read and set through the private `DisplayServices` framework (`DisplayServicesGetBrightness` / `DisplayServicesSetBrightness`). Private APIs can change between macOS releases; `--selftest-hardware` tells you if they did.
- **Automations** use only what macOS tells every app anyway — which apps are running (NSWorkspace's launch and quit notifications), whether a display is connected, the power source and the clock. No permission prompts, nothing polled.
- **The keyboard shortcut** is a system hot key (Carbon `RegisterEventHotKey`), not an event tap: SleepLess sees that one combination and nothing else you type. Recording it refuses plain keys, so a shortcut can never swallow ordinary typing.
- **Notifications** are sent only if you turn them on, and only for a timer ending or a safety rule turning lid-closed mode off.
- **The URL scheme** is an input boundary: `sleepless://on|off|toggle|lid` with `minutes=` (1 – 1440), `until=HH:MM` or `on=0|1` and nothing else — unknown verbs, parameters, duplicates, paths and fragments are dropped without doing anything.
- **The root helper** is a short, readable shell script. It only ever runs `pmset -g` and `pmset -a disablesleep 0|1`, plus `sleepless-led off|on` for the charging light (that tool only ever writes the one SMC key that picks the MagSafe light's colour). It is installed by `/bin/sh sleepless-helper.sh install <user>` after the system's authorization prompt (Authorization Services, `system.privilege.admin` — the same sheet installers use, with Touch ID where macOS offers it), and the app checks that the installed copy is byte-for-byte identical to the one in its bundle before trusting it.
- **The helper updates itself only from signed files.** When a new version of SleepLess changes it, the app writes its bundle path to a request file; the root helper copies the files into a root-owned folder first, runs its own root-owned verifier (`sleepless-verify`, compiled from [`tools/helper-verify.swift`](tools/helper-verify.swift)) against the root-owned copy of the publisher key — manifest signature, every file's hash, no downgrade — and only then installs them, each with a rename. Anything else is ignored, and the panel offers the setup card instead. The prompt at setup is therefore the only one there will ever be.
- **The request file** (`/Library/Application Support/SleepLess/lid`) is owned by your user in a root-owned directory. Any process running as your user could write `1` to it. The impact is limited to keeping the Mac awake (with the lid closed) while that process keeps rewriting the file, and the 90 s watchdog still applies. The helper reads only the first byte.
- The app is **not sandboxed** (it needs IOKit and the private brightness API) and official builds are Developer ID signed and notarized by Apple.

## License

**SleepLess is copyright © 2026 Weta Technologies Limited. All rights reserved. Developed by Weta Technologies Limited · GitHub: [CyborgFingers](https://github.com/CyborgFingers).**

SleepLess is **freeware**: you may download and use it free of charge on any Macs you own or control, for personal or business use. You may not modify, decompile, redistribute, sell or host it; please share the [official download](https://github.com/Weta-Technologies/SleepLess/releases/latest) instead. The source is published so you can see exactly what SleepLess does. It is not open source, and viewing it gives no rights beyond the licence. The installer asks you to accept the licence before installing.

- [Licence agreement](LICENSE) (governed by New Zealand law)
- [Privacy policy](PRIVACY.md): SleepLess collects nothing
- [Trademark policy](TRADEMARKS.md) · [Security policy](SECURITY.md) · [Contributing](CONTRIBUTING.md) · [Notices](NOTICE.md)


Apple, Mac, macOS and MagSafe are trademarks of Apple Inc. SleepLess is not affiliated with or endorsed by Apple Inc.
