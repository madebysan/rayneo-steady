# Development guide

How RayNeo Steady is built, how its tracking works, and what has and hasn't been verified. Start with the [README](../README.md); building, packaging and the source map are in [how it works](how-it-works.md).

## Scope

- Native AppKit controls and Metal output; macOS 15 or later on Apple Silicon.
- Screen size from 40 to 100%, starting at 80%, in exact one-point steps.
- Three motion modes: Off, Pinned (holds a direction) and Steady Follow (relaxes toward deliberate turns), plus Recenter and stillness calibration.
- A calibration grid and a windowed preview that work without Screen Recording permission or glasses.
- Desktop mode copies an existing Mac screen, pointer included, through ScreenCaptureKit.
- Settings and processing stay on the Mac: no account, server or analytics.

The app never changes macOS display settings. Live desktop output needs a source screen and the glasses as separate displays; with a mirrored arrangement, use the grid or the preview. It doesn't create a virtual monitor or support closed-lid use.

## Signing

Builds sign with a Developer ID Application identity; set `STEADY_SIGNING_IDENTITY` to choose one. The bundle identifier stays fixed so Screen Recording permission carries across builds. The app isn't sandboxed. `script/package_dmg.sh` refuses to overwrite an existing DMG. Releases so far are signed but not notarized, so macOS warns on first launch.

## Tracking

- **Sensor data:** the vendored SDK reports gyroscope rates in degrees per second. On the Air 4 Pro, device ticks are 100 microseconds, not milliseconds (a five-second probe measured 2,484 samples over 50,000 ticks); two regression tests cover the conversion. Invalid and duplicate ticks are dropped.
- **Pinned** integrates calibrated gyroscope data, so it can drift over time; there's no positional tracking or magnetometer correction. Calibration measures temporary software bias only.
- **Sensor panel:** shows connection state, sample rate (about 500 per second) and calibration status, and offers horizontal and vertical inversion, 45° alignment and tilt compensation. These are experimental and reset when the app quits.
- **Margins:** black margins leave room for motion compensation; a large turn can move a pinned screen out of view, and Recenter brings it back.

## Refined tracking

The **Refined tracking** checkbox switches drivers live without recalibrating or recentering:

- A `CAMetalDisplayLink` schedules rendering against the output display with one-frame latency, up to 120 Hz. The original MTKView timer is inactive, and queued callbacks are guarded so the two drivers never use the Metal layer at once.
- A temporary pose prediction looks ahead at most 8 ms and adds at most 0.5°. It never changes the saved anchor or the integrated pose, and samples 20 ms or older aren't predicted. A light 40 Hz velocity filter feeds only the prediction.

Timing samples from Metal's `presentedTime` (180-frame windows) measure draw-to-presentation time, not full motion-to-photon latency:

| Path | Settled fps | 95th-percentile frame interval | Mean draw-to-presentation |
| --- | ---: | ---: | ---: |
| Original | 113.1 | 16.7 ms | 27.2 ms |
| Display link, no prediction | 120.0 | 8.3 ms | 33.2 ms |
| Display link with prediction | 100.0 | 16.7 ms | 31.5 ms |

Sustained 120 fps isn't established, and presentation delay didn't drop; prediction is meant to cover part of the remaining pose age.

## Tests and verification

`swift test` runs 13 tests: exact size steps and bounds, pinned inverse rotation, follow settling, invalid samples, timestamp wrap, duplicates and sleep gaps, stationary bias, tracking off, the Air 4 Pro device clock, and bounded prediction (8 ms horizon, 0.5° cap, recenter, settling and Off mode).

Checked on real glasses: the two core features (a smaller screen that stays in place, with fine shake remaining), live desktop capture with the pointer and clicks on the source screen, Stop and Start, and launching the packaged app. Not established: physical axis mapping across units, long-term drift, motion-to-photon latency, and the quality of Steady Follow. Rendering on the same display used for capture isn't supported.

## Dependencies

The C++ sensor transport is vendored unchanged from [verncat/RayNeo-Air-3S-Pro-OpenVR](https://github.com/verncat/RayNeo-Air-3S-Pro-OpenVR) at `dfd2e8abab7052d88a1047266d89260347d0dd67` (API 1.4.1), under its MIT license (`Sources/CRayNeo/LICENSE`, credited in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)). Only the transport and C header are included. The SDK doesn't support choosing an interface on macOS, so the app selects the Air family's USB IDs and uses native HID discovery. Screen capture follows [Apple's ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos); see also [CAMetalDisplayLink](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink).

The app sends no firmware changes, calibration writes or display-mode commands to the glasses; Start and Stop only enable and disable the sensor stream. Close other glasses apps before connecting.
