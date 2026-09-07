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
| `TrainingApp/` | The Xcode app target: `@main` App struct, entitlements, asset catalog. Thin glue only. |
| `TrainingAppKit/` | Local Swift package with the app's views and view models. Consumes `TrainingKit` as a remote SPM dependency, so it's `swift test`-able independent of Xcode. |
| `project.yml` | [xcodegen](https://github.com/yonaskolb/XcodeGen) spec for `TrainingApp.xcodeproj`, which is generated, not committed. |

## Getting started

```bash
brew install xcodegen   # if not already installed
xcodegen generate
open TrainingApp.xcodeproj
```

Run `xcodegen generate` again after pulling changes to `project.yml`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the branching strategy and CI requirements.
