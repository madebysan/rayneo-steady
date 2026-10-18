# How RayNeo Steady works

Using it, building and packaging, and the source map. The short version is the [README](../README.md).

## Using it

1. Connect the glasses and close competing glasses apps.
2. Choose **My Mac desktop**, your Mac screen as **Source**, and **SmartGlasses** as **Output**.
3. Start in Glasses and grant Screen Recording access. Frames stay local; the app does not save or upload recordings.
4. Let calibration finish with the glasses still, then put them on and Recenter.

**80%** is a comfortable starting size. The buttons adjust by exactly one percentage point. Pinned holds a direction; Steady Follow follows deliberate turns. Refined tracking can be switched on/off without recalibration. The calibration grid is an optional size guide.

- **Control–Command–1:** show controls.
- **Control–Command–R:** recenter.
- **Control–Command–S:** stop output.

The app leaves macOS display settings alone. Live desktop output needs separate source and output displays already configured in macOS. The grid and windowed preview also work with a mirrored display arrangement. Keep the pointer on the source desktop for normal interaction.

## Building and testing

From this project folder:

```sh
swift test
script/build_and_run.sh
```

Create a Release app and installer:

```sh
script/build_app.sh release
script/package_dmg.sh
```

Xcode command-line tools and a Developer ID Application signing identity are required by the packaging scripts. `STEADY_SIGNING_IDENTITY` can select an existing identity. The scripts do not create credentials or upload to Apple. Packaging writes to `releases/` and refuses to overwrite an existing installer.

The built app, DMGs and intermediate iconset are generated artifacts excluded from Git. Git tracks the source, tests, build scripts, documentation and icon assets. The app and installer exist only after building locally.

## Source map and records

| Location | Owns |
| --- | --- |
| `Sources/RayNeoSteady/` | AppKit controls, Metal rendering, ScreenCaptureKit, sensor service |
| `Sources/SteadyCore/` | Screen sizing, device-clock conversion, motion math and prediction |
| `Sources/CRayNeo/` | Vendored MIT-licensed RayNeo SDK and C interface |
| `Tests/SteadyCoreTests/` | Thirteen tests for sizing, motion, timing and bounded prediction |
| `Assets/` | Icon master and PNG/ICNS assets |
| [DESIGN.md](../DESIGN.md) | Native interface and icon direction |
| [docs/DEVELOPMENT.md](DEVELOPMENT.md) | Tracking design, runtime measurements and what's verified |

Tested on real glasses: the two core features work, with some fine shake remaining. The timing figures are runtime samples, not a controlled latency benchmark. Notarization and capturing the same display used for output are still open.
