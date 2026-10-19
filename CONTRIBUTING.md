# Contributing to MealPrep Planner

## Branches

| Branch | Purpose |
| --- | --- |
| `main` | Released, tagged builds only. Updated from `develop` at release time. |
| `develop` | Integration branch. Every feature lands here first. |
| `feature/<name>-<topic>` | New features, for example `feature/mingchen-pantry-screen`. |
| `fix/<name>-<topic>` | Bug fixes, for example `fix/junhao-expiry-window`. |
| `test/<name>-<topic>` | Tests that do not change app code. |
| `docs/<name>-<topic>` | Documentation and report changes. |

Names and topics are lower case words joined by `-`, for example `feature/junhao-core-data` and `feature/zhengyang-root-tabs`.

Branch from the latest `develop`, keep the branch focused on one feature, and open a pull request back into `develop`. Another team member reviews the PR before it is merged. Do not push directly to `main` or `develop`.

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional scope>): <summary in the imperative, lower case>
```

Types: `feat`, `fix`, `test`, `docs`, `refactor`, `chore`. Scopes follow the layers: `domain`, `data`, `ui`, `widget`, `app`.

Small changes use the subject line only. Larger changes add a blank line and 2–4 bullets, each starting with `- `, lower case and without a full stop. If you ran the tests, end with a `Validation:` line.

```
feat(domain): add repository error type

- add RepositoryError for not found, read, write and store failures
- document that the repository protocol reports failures as RepositoryError

Validation: all tests passed on the iPhone 17 Pro simulator.
```

Merge commits use `merge: integrate <branch> into development`.

Commit under your own Git identity so the history shows who did what.

## File headers

Every new Swift file starts with a header line naming its author and the date it was created, followed by a blank line:

```swift
//  Created by Junhao Huang on 2026/10/17.

import Foundation
```

## Using the repository in screens

`AppRootView` opens the Core Data store at launch and puts an `AppDependencies` in the environment. Screens read and write through it and reload whenever data changes:

```swift
@Environment(AppDependencies.self) private var dependencies

var body: some View {
    List { /* ... */ }
        .task(id: dependencies.changes.version) { await viewModel.load() }
}
```

Always write through `dependencies.repository`. Each successful write bumps `changes.version` and refreshes the widget snapshot, so do not call the widget refresher from a screen.

## SwiftUI previews

`InMemoryMealRepository` and `PreviewData` are compiled into debug builds of the app, so previews never need Core Data:

```swift
#Preview("Sample week") {
    TodayView().environment(AppDependencies.preview())
}

#Preview("Empty") {
    TodayView().environment(AppDependencies.preview(repository: InMemoryMealRepository()))
}
```

`PreviewData` covers a prepared breakfast, lunch and dinner today, meals on the next days, and stock that expires today, within three days, has expired, or has no date. The tomato meals match the demo: 300 g and 250 g needed, 200 g in stock, 350 g to buy. To preview an error state, call `repository.fail(.read, with: .readFailed)` in the preview's `.task`. Wrap any preview code that uses these types in `#if DEBUG`, because they are not in release builds.

## Widget extension and App Group

- The `MealPrepPlannerWidgetExtension` target lives in `WidgetExtension/`. Its widget is a placeholder that shows the next meal; B replaces the provider and views there.
- The extension reads `WidgetSnapshotStore().load()` and must not import Core Data or the Domain layer. The files in `Sources/Shared/` belong to both the app and the extension target. If you add a file there, tick both targets.
- Use `AppGroupConfiguration.widgetKind` as the widget kind, so the app's reload requests reach it.
- Both targets use the App Group `group.com.manbo.MealPrepPlanner` (`Sources/App/MealPrepPlanner.entitlements` and `WidgetExtension/MealPrepPlannerWidget.entitlements`). The simulator needs no development team. To run on a device, choose your team under Signing & Capabilities for both targets.

## Before opening a pull request

1. Merge or rebase the latest `develop` into your branch.
2. Build in Xcode with zero warnings.
3. Run all tests with ⌘U and make sure they pass.
4. Use `InMemoryMealRepository` (in `Sources/Data/InMemory`, debug builds only) for use case and ViewModel tests instead of Core Data.

## Xcode project file IDs

`project.pbxproj` uses hand-written object IDs (`A000…`). Two branches that pick the same ID will conflict on merge, so each member adds new files only in their own range:

| Member | Build file IDs | File reference IDs |
| --- | --- | --- |
| A (Junhao) | `A…140`–`A…14F` | `A…240`–`A…24F` |
| B (Zhengyang) | `A…150`–`A…15F` | `A…250`–`A…25F` |
| C (Mingchen) | `A…160`–`A…16F` | `A…260`–`A…26F` |

Branches created before this rule already overlap: `feature/junhao-core-data` and `feature/zhengyang-root-tabs` both use `A…20B`. Merge those into `develop` one at a time and renumber the second one when resolving the conflict. If you let Xcode add a file instead, it generates random IDs, which is also fine.

A's range is used up. A's new objects from `feature/junhao-app-group` on use random 24-character IDs, like the ones Xcode generates.
