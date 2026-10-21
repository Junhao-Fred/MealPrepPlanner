# MealPrepPlanner

A SwiftUI meal planner with Today, Meal Plan, Pantry and Shopping List tabs, Core Data persistence, and a WidgetKit extension. Shopping quantities combine unfinished meal requirements and subtract valid pantry stock. Marking a meal as prepared updates its status; stock deductions are confirmed separately through Pantry.

## Requirements and current verification

Use a Mac with full Xcode, its command-line tools, and an installed iOS Simulator runtime. The tests use **Swift Testing**, which Apple includes in [Xcode 16 and later](https://developer.apple.com/documentation/xcode/testing). This framework requirement does not establish a tested minimum Xcode version for this project.

| Setting | Checked-in value |
| --- | --- |
| Project / shared scheme | `MealPrepPlanner.xcodeproj` / `MealPrepPlanner` |
| Deployment target | iOS 17.0; iPhone and iPad |
| Swift language mode | `SWIFT_VERSION = 5.0` |
| App / test / extension targets | `MealPrepPlanner` / `MealPrepPlannerTests` / `MealPrepPlannerWidgetExtension` |
| Test configuration | Debug, hosted by the app |
| Dependencies | Apple frameworks; no package manifest, CocoaPods setup or external package references are checked in |

Sources: [build settings](MealPrepPlanner.xcodeproj/project.pbxproj) and [shared scheme](MealPrepPlanner.xcodeproj/xcshareddata/xcschemes/MealPrepPlanner.xcscheme). Tool metadata contains versions 26.6 and 27.1; these are authoring metadata, not recorded successful build results.

The C17 documentation was checked against source on Windows. Earlier changes passed Swift syntax parsing; **Xcode compilation, test execution, signing, widget sharing and device accessibility remain pending Mac verification**. Windows Swift alone cannot build this iOS app. Record the exact working macOS/Xcode/runtime combination in the verification section after running it.

## Open and run

In a macOS terminal:

```sh
git clone https://github.com/Junhao-Fred/MealPrepPlanner.git
cd MealPrepPlanner
git fetch origin
```

Use the reviewed branch containing this README and the integrated features. During C17 review this is `docs/mingchen-handoff`, based on C16 (`59dad1b`). Once that branch is pushed, select it with `git switch docs/mingchen-handoff`. At the time of writing, `develop` is `1d3d7b2` and does not yet contain these integrated features. After merge, use the agreed integration branch.

```sh
xcodebuild -version
xcode-select -p
xcodebuild -list -project MealPrepPlanner.xcodeproj
open MealPrepPlanner.xcodeproj
```

1. Select the **MealPrepPlanner** scheme and an available iPhone simulator running iOS 17 or later. Use a simulator supported by your installed Xcode.
2. Check signing as described below if Xcode reports capability or provisioning errors.
3. Choose **Product > Run** (`Cmd-R`). A fresh installation opens with empty data; create meals and ingredients through the tabs.
4. For populated SwiftUI previews, open [RootTabView.swift](Sources/App/RootTabView.swift) and use its Today or Empty preview. Preview dependencies use the in-memory repository and the `MealPrepPlannerPreviews` defaults suite.

[AppDependencies.live()](Sources/App/AppDependencies.swift) opens the persistent SQLite store through [PersistenceController](Sources/Data/CoreData/PersistenceController.swift). Preview fixtures are Debug-only and do not seed the normal app database.

## Signing and App Group

| Identifier | Checked-in value |
| --- | --- |
| App bundle ID | `com.manbo.MealPrepPlanner` |
| Widget bundle ID | `com.manbo.MealPrepPlanner.Widget` |
| Test bundle ID | `com.manbo.MealPrepPlannerTests` |
| Shared App Group | `group.com.manbo.MealPrepPlanner` |
| Widget kind / snapshot key | `MealPrepPlannerWidget` / `mealWidgetSnapshot` |

For a physical device, select a development team in **Signing & Capabilities** for the app and widget extension, using the same team. Automatic signing is enabled in the project, but no `DEVELOPMENT_TEAM` is checked in. Use a team that can provision the required App Group. Apple's [team assignment instructions](https://help.apple.com/xcode/mac/current/en.lproj/dev23aab79b4.html) and [App Group configuration guide](https://developer.apple.com/documentation/xcode/configuring-app-groups) describe the account setup.

Enable **App Groups** on both targets and select the same registered group. Check all three locations together:

- [App entitlements](Sources/App/MealPrepPlanner.entitlements)
- [Widget entitlements](WidgetExtension/MealPrepPlannerWidget.entitlements)
- [AppGroupConfiguration.identifier](Sources/Shared/AppGroupConfiguration.swift)

If the checked-in bundle IDs or group are unavailable to your team, configure unique app and widget bundle IDs and a group belonging to that team. Keep the widget bundle ID prefixed by the app bundle ID, update the test bundle ID if necessary, and change the group in all three locations above. Record any local identifier changes for the reviewer.

The widget reads a JSON snapshot from App Group `UserDefaults`; the app's Core Data database remains in its normal app container. [WidgetSnapshotRefresher](Sources/App/WidgetSnapshotRefresher.swift) requests a timeline reload after snapshot content changes. To check sharing, run the app, add a future meal, then add the **Meal Prep Planner** widget through the device/simulator widget gallery. Supported families are small, medium and Lock Screen rectangular. Reopen the app after changing data and allow WidgetKit to schedule its refresh; a successful app write alone does not prove widget delivery.

## Run automated tests

In Xcode, keep the **MealPrepPlanner** scheme and choose **Product > Test** (`Cmd-U`). The shared scheme enables `MealPrepPlannerTests` in Debug. This matters because the in-memory repository and preview fixtures are compiled only with `DEBUG`.

For a repeatable command-line run, list destinations and copy an available iOS Simulator UUID:

```sh
xcodebuild -showdestinations -project MealPrepPlanner.xcodeproj -scheme MealPrepPlanner
xcrun simctl list devices available
```

Run the following in the repository root, replacing the placeholder with that UUID. These commands are for macOS zsh/bash:

```sh
SIMULATOR_ID='PASTE-AVAILABLE-SIMULATOR-UUID-HERE'
RESULT_PATH="build/MealPrepPlanner-$(date +%Y%m%d-%H%M%S).xcresult"
mkdir -p build
xcodebuild test \
  -project MealPrepPlanner.xcodeproj \
  -scheme MealPrepPlanner \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath DerivedData \
  -resultBundlePath "$RESULT_PATH"
```

Check the command's exit status and test summary, then open the generated `.xcresult` in Xcode. Use a new result path for each run. Both `build/` and `*.xcresult` are ignored by Git. The command is a documented procedure pending a Mac run, not a recorded passing result.

For a focused rerun, add `-only-testing:MealPrepPlannerTests/ShoppingListUseCaseTests` to the same `xcodebuild test` command. Other useful suites are:

| Area | Suites |
| --- | --- |
| Pantry validation, usage and input | `PantryUseCaseTests`, `PantryViewModelTests`, `PantryQuantityParserTests`, `IngredientEntryDraftTests` |
| Meal scheduling, querying and save failures | `PlanMealUseCaseTests`, `MealPlanQueryTests`, `MealPlanViewModelTests`, `MealEntryTests` |
| Shopping boundaries, failures and refresh | `ShoppingListUseCaseTests`, `ShoppingListViewModelTests`, `FeatureDataRefreshTests` |
| Persistence and restart behavior | `CoreDataMealRepositoryTests`, `CoreDataUpsertTests`, `CoreDataRegressionTests`, `RepositoryErrorMappingTests` |
| Today and widgets | `TodayViewModelTests`, `MarkMealPreparedUseCaseTests`, `WidgetSnapshotTests`, `WidgetSnapshotRefresherTests`, `WidgetTimelineTests` |

Tests live in [Tests/MealPrepPlannerTests](Tests/MealPrepPlannerTests). Core Data tests include temporary SQLite stores; widget tests use temporary defaults suites. There is no separate UI-test target, and these tests do not establish VoiceOver behavior or real App Group provisioning.

## Manual smoke check

Use a fresh test installation with no existing rice stock or meal demand. Schedule test meals later today so they appear in Today and within the shopping window.

1. In Pantry, add **Rice, 200 g**, with no expiry date.
2. In Meal Plan, create two meals requiring **300 g** and **250 g** of Rice. Shopping List should show **350 g** to buy and **2** unfinished meals.
3. In Pantry, confirm usage of **50 g**. Remaining stock should be **150 g** and the shopping shortfall **400 g**.
4. In Today, open the **300 g** meal and select **Mark as Prepared**. Meal Plan should show Prepared; Shopping List should show **100 g** to buy and **1** unfinished meal. Pantry should still contain **150 g**.
5. Stop and relaunch the app without uninstalling it. Confirm that the plans, completion status and remaining stock persist.
6. In Add Meal, enter an invalid quantity in the second ingredient row and save. Check that the second quantity field receives keyboard focus and an error appears. Edit the input and confirm the old message clears. With VoiceOver, check that each row's quantity, unit and removal controls identify the correct ingredient. Also check large text and dark mode on the device.
7. Add the widget and check the remaining future meal. Keep widget verification separate from the in-app checks.

The shopping window is `[local midnight today, local midnight seven calendar days later)`. Stock is valid through its expiry day. Different units remain separate; there is no g/kg conversion.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `xcodebuild` cannot find Xcode or a destination | Select the full Xcode installation in Xcode Settings > Locations; install a simulator runtime and repeat `-showdestinations`. |
| `No such module 'Testing'` | Check the selected Xcode toolchain and Swift Testing support. |
| Signing or App Group provisioning fails | Check both targets' team, bundle IDs, capabilities and all three group identifier locations above. |
| Tests cannot find `InMemoryMealRepository` | Run the shared scheme in Debug; check the `DEBUG` compilation condition. |
| Widget is empty or stale | Open the app, create a future unfinished meal, check matching groups and inspect Xcode console messages in the `WidgetSnapshot` category. |
| “Can't Open Your Data” appears | Retry, then inspect the Core Data error in Xcode. Keep the failing store for diagnosis; uninstalling the app removes its saved data. |
| Previews contain meals but the running app is empty | Previews use sample fixtures; create data in the persistent app through its forms. |

## Independent verification record

An A/B teammate should follow these instructions from a clean checkout on a Mac and record the actual outcome below. Source settings have been checked; teammate confirmation and execution results have not yet been supplied.

- Reviewer / date: **Pending**
- Branch / commit reviewed: **Pending**
- macOS / Xcode version and build: **Pending**
- Simulator or device / iOS version: **Pending**
- Signing and identifier changes: **Pending**
- Test summary and `.xcresult` location: **Pending**
- Smoke check, persistence and widget outcome: **Pending**
- VoiceOver, large text and dark mode outcome: **Pending**
- Problems found and follow-up: **Pending**
