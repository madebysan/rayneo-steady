<h1>RayNeo Steady</h1>

<p>A Mac utility that makes a RayNeo Air 4 Pro desktop smaller and steadier.<br>
It mirrors a Mac screen into the glasses with precise sizing and motion compensation.</p>

<p><strong>Version 0.2.1</strong> · macOS 15+ · Apple Silicon</p>

<p>
  <img src="https://img.shields.io/badge/Swift-f05138" alt="Swift">
  <img src="https://img.shields.io/badge/AppKit-0066cc" alt="AppKit">
  <img src="https://img.shields.io/badge/macOS-000000" alt="macOS">
</p>

RayNeo Steady shows your Mac desktop in RayNeo Air 4 Pro glasses at a size you can read, and holds it steadier when you move your head.

- Set the screen size in steps of one percent.
- Pinned holds the screen in one direction; Steady Follow follows deliberate turns.
- Frames stay on your Mac and are never saved or uploaded.

## How it works

Connect the glasses, choose your Mac screen as the source and the glasses as the output, and start. Let calibration finish with the glasses still, then put them on and recenter. `Control Command 1` shows the controls, `Control Command R` recenters and `Control Command S` stops. The app leaves macOS display settings alone, so live output needs separate source and output displays. Details are in [docs/how-it-works.md](docs/how-it-works.md).

## Privacy

Mirroring the desktop needs Screen Recording permission; the calibration grid and preview window don't. Frames go straight to the glasses and are not saved. The app makes no network connections and has no update checker.

## Limits

The build is Developer ID signed but not yet notarized, so macOS will warn on first launch. Some fine shake remains, and capturing the same display used for output isn't supported.

## Install

It needs an Apple Silicon Mac on macOS 15 or later, and there is no published release yet. Build it with the Xcode command-line tools: `script/build_and_run.sh` runs it, and `script/build_app.sh release` plus `script/package_dmg.sh` make a signed installer (they need a Developer ID Application identity). Tests run with `swift test`. Updates are manual: build or install the new version over the old one.

---

[MIT](LICENSE). RayNeo Steady includes the [RayNeo SDK by verncat](https://github.com/verncat/RayNeo-Air-3S-Pro-OpenVR); its MIT license is in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Made by [santiagoalonso.com](https://santiagoalonso.com)
