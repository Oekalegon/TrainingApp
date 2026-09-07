# TrainingApp

Companion iOS app for [TrainingKit](https://github.com/Oekalegon/TrainingKit): a personal,
single-athlete, read-only viewer of training data synced via HealthKit and CloudKit. iOS 26+,
iPhone only.

MVP 1 shows a rolling fitness trend (CTL/ATL/TSB) alongside a week-by-week view of completed and
planned activities, with a basic activity detail screen and a read-only athlete account screen.
See [`docs/design/trainingApp-design.md`](docs/design/trainingApp-design.md) for the full design.

## Project layout

| Path | Purpose |
|---|---|
| `iOS/` | The iOS app target: `@main` App struct, entitlements, asset catalog. Thin glue only. A macOS companion app will get its own `macOS/` sibling folder later. |
| `TrainingAppKit/` | Local Swift package with the app's views and view models, shared across platforms. Depends on `TrainingKit` as a remote SPM dependency (overridden to the local sibling checkout automatically when you open `TrainingApp.xcworkspace` — see below), so it's `swift test`-able independent of Xcode. |
| `project.yml` | [xcodegen](https://github.com/yonaskolb/XcodeGen) spec for `TrainingApp.xcodeproj`, which is generated, not committed. |
| `TrainingApp.xcworkspace` | Combined workspace: `TrainingApp.xcodeproj` plus a sibling reference to the `../TrainingKit` checkout, so you can edit the package and the app together. Committed — this is authored, not generated. |
| `Config/Local.xcconfig` | Committed base build config (currently just `CODE_SIGN_STYLE = Automatic`) that optionally includes `Local.Secrets.xcconfig`. |
| `Config/Local.Secrets.xcconfig` | **Not committed** — your own `DEVELOPMENT_TEAM`. Copy from `Local.Secrets.xcconfig.example`. Without it, simulator builds still work fine (ad-hoc "Sign to Run Locally"); you only need it to run on a physical device or archive for TestFlight. |

## Getting started

Requires `TrainingKit` checked out as a sibling directory (`../TrainingKit` relative to this repo).

```bash
brew install xcodegen   # if not already installed
cp Config/Local.Secrets.xcconfig.example Config/Local.Secrets.xcconfig   # then fill in your Team ID
xcodegen generate
open TrainingApp.xcworkspace
```

Opening the workspace (not the bare `.xcodeproj`) is what makes Xcode use your local `TrainingKit`
checkout instead of fetching the remote dependency — edit either project and both see the change
immediately. Run `xcodegen generate` again after pulling changes to `project.yml` — since signing
now comes from `Config/Local.xcconfig` rather than being baked into the generated project, your
Team ID survives every regeneration instead of getting wiped out.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the branching strategy and CI requirements.
