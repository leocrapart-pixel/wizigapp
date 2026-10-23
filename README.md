# WizigApp

A [Wizig](https://github.com/wizig-org/wizig) app: **random little calculators**, just to test
native Android hosting. The math is shared Zig code in `lib/`; the UI is Jetpack Compose;
the two are glued together by code-generated typed bindings.

## What it calculates

| Card | Zig API (`lib/main.zig`) | Input | Output |
| --- | --- | --- | --- |
| Random number | `randomInt` | `min max` | uniform integer |
| Dice | `rollDice` | `2d6`, `4` (default d6) | every face + sum |
| Coin flip | `coinFlip` | — | Heads / Tails |
| Password | `password` | `16` | one char per class, no lookalikes |
| Tip split | `tipSplit` | `bill tip% people` | tip / total / per person |
| BMI | `bmi` | `kg cm` | value + band |
| Compound interest | `compound` | `principal rate% years` | total + interest |

Every `pub fn` in `lib/` is discovered by `wizig codegen` and shows up as a typed method on
`dev.wizig.WizigGeneratedApi` for the host to call over JNI — no hand-written FFI plumbing.

## Build (GitHub Actions)

`.github/workflows/android.yml` builds a debug APK on every push to `main` (or manually via
*Run workflow*) and uploads it as the `wizigapp-debug-apk` artifact.

CI pins everything that affects the output:

| Tool | Pinned version | Why |
| --- | --- | --- |
| Zig | `0.16.0` | the vendored Wizig runtime template uses `std.atomic.Mutex`, which 0.15.x lacks |
| Wizig CLI | `nightly-20261023` (`c768ed10`), sha256-verified | scaffold/codegen version must match the vendored `.wizig/` sources |
| JDK | Temurin 21 | AGP 9 / Gradle 9.2.1 |
| Android SDK | platform 36, build-tools 36 (preinstalled on `ubuntu-24.04`) | `compileSdk = 36` |
| NDK | `27.3.13750724` (runner default) | generated JNI shim builds via CMake |

## Local build

Prerequisites: Zig 0.16.0, JDK 21, Android SDK (platform 36), NDK `27.3.13750724`.

```sh
zig test lib/main.zig                       # logic checks
wizig codegen . --allow-toolchain-drift     # regenerate bindings after editing lib/
cd android && ./gradlew :app:assembleDebug  # APK -> android/app/build/outputs/apk/debug/
```

Run with `adb install -r android/app/build/outputs/apk/debug/app-debug.apk`.

## Layout

- `lib/`: shared Zig logic (the only file the app author edits per calculator).
- `android/`: Compose host; `app/build.gradle.kts` also drives the Zig `build-lib` cross-compile
  into `.wizig/generated/android/jniLibs/` before CMake links the JNI shim.
- `.wizig/sdk`, `.wizig/runtime`: vendored framework sources (keep in sync with the CLI version).
- `.wizig/generated/`: build artifacts from `wizig codegen`, git-ignored.

## Notes

- Inputs are single strings (`"100 15 2"`) because the generated bridge carries one value per
  method; the host formats them, Zig parses and validates them.
- Randomness comes from the OS `getrandom` syscall in Zig. The comment in `fillRandom` marks the
  ceiling: an iOS host would need its own entropy path before this module compiles for it.
- `std.atomic.Mutex` vs `toolchains.toml`: upstream advertises Zig 0.15.1, but the 20261023
  nightly's runtime template already needs 0.16.0 — CI pins what actually compiles.
