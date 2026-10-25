# MealPrepPlanner

A SwiftUI meal planner with Today, Meal Plan, Pantry and Shopping List tabs, Core Data persistence, and a WidgetKit extension. Shopping quantities combine unfinished meal requirements and subtract valid pantry stock, converting matching units (g/kg, ml/l) and simple plurals. Marking a meal as prepared deducts its recipe from pantry stock, soonest expiry first, and can be undone. Pantry items and planned meals can be edited and deleted, and the app schedules local reminders before stock expires.

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

Sources: [build settings](MealPrepPlanner.xcodeproj/project.pbxproj) and [shared scheme](MealPrepPlanner.xcodeproj/xcshareddata/xcschemes/MealPrepPlanner.xcscheme).

Verified on macOS 26.7.1 with Xcode 27.1 (27A9275) and the iPhone 17 Pro simulator on iOS 26.4: the app and widget build with 0 warnings and all 181 tests pass. Signing on a physical device and VoiceOver have not been verified; see the record at the end.

## Open and run

In a macOS terminal:

```sh
git clone https://github.com/Junhao-Fred/MealPrepPlanner.git
cd MealPrepPlanner
git fetch origin
```

Use the `develop` branch, which contains the integrated features: `git switch develop`. If you received the source archive instead, open the unzipped `MealPrepPlanner` folder directly; no Git checkout is needed.

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

Check the command's exit status and test summary, then open the generated `.xcresult` in Xcode. Use a new result path for each run. Both `build/` and `*.xcresult` are ignored by Git.

For a focused rerun, add `-only-testing:MealPrepPlannerTests/ShoppingListUseCaseTests` to the same `xcodebuild test` command. Other useful suites are:

| Area | Suites |
| --- | --- |
| Pantry validation, usage, grouping and deletion | `PantryUseCaseTests`, `PantryViewModelTests`, `PantryQuantityParserTests`, `IngredientEntryDraftTests`, `PantryGroupingTests`, `PantryDeleteTests` |
| Meal scheduling, editing, querying and deletion | `PlanMealUseCaseTests`, `MealPlanQueryTests`, `MealPlanViewModelTests`, `MealEntryTests`, `MealPlanDeleteTests`, `EditingAndFollowUpTests` |
| Ingredient matching and stock adjustment | `IngredientMatchingTests`, `AdjustPantryForMealTests`, `MarkMealPreparedUseCaseTests` |
| Shopping boundaries, failures and refresh | `ShoppingListUseCaseTests`, `ShoppingListViewModelTests`, `FeatureDataRefreshTests` |
| Persistence and restart behavior | `CoreDataMealRepositoryTests`, `CoreDataUpsertTests`, `CoreDataRegressionTests`, `RepositoryErrorMappingTests`, `InMemoryMealRepositoryTests` |
| Today, widgets and reminders | `TodayViewModelTests`, `ExpiryRulesTests`, `WidgetSnapshotTests`, `WidgetSnapshotRefresherTests`, `WidgetTimelineTests`, `ExpiryReminderTests` |

Tests live in [Tests/MealPrepPlannerTests](Tests/MealPrepPlannerTests). Core Data tests include temporary SQLite stores; widget tests use temporary defaults suites. There is no separate UI-test target, and these tests do not establish VoiceOver behavior or real App Group provisioning.

## Manual smoke check

Use a fresh test installation with no existing rice stock or meal demand. Schedule test meals later today so they appear in Today and within the shopping window.

1. In Pantry, add **Rice, 200 g**, with no expiry date.
2. In Meal Plan, create two meals requiring **300 g** and **250 g** of Rice. Shopping List should show **350 g** to buy and **2** unfinished meals.
3. In Pantry, confirm usage of **50 g**. Remaining stock should be **150 g** and the shopping shortfall **400 g**.
4. In Meal Plan, open the **300 g** meal and select **Mark as Prepared**. The details screen should report that the pantry was **150 g** short. Pantry should no longer list Rice; Shopping List should show **250 g** to buy and **1** unfinished meal.
5. In Shopping List, tap the check mark next to Rice. Pantry should show **Rice, 250 g** and the shopping list should be empty.
6. In Pantry, add **Rice, 1 kg**. Pantry should show one Rice item of **1.25 kg** listing both batches. Swipe it right to edit a batch, and left to delete the item after confirming.
7. Stop and relaunch the app without uninstalling it. Confirm that the plans, completion status and remaining stock persist.
8. In Add Meal, enter an invalid quantity in the second ingredient row and save. Check that the second quantity field receives keyboard focus and an error appears. Edit the input and confirm the old message clears. With VoiceOver, check that each row's quantity, unit and removal controls identify the correct ingredient. Also check large text and dark mode on the device.
9. Add the widget and check the remaining future meal. Keep widget verification separate from the in-app checks.

The shopping window is `[local midnight today, local midnight seven calendar days later)`. Stock is valid through its expiry day. Names ignore case, spaces and simple plurals. Units convert within mass (mg, g, kg, oz, lb), volume (ml, cl, dl, l, tsp, tbsp, cup) and count (piece, pcs, count, each, item); other units match only themselves.

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
| No expiry reminders appear | Reminders need notification permission and an expiry date; they fire at 9:00 the day before expiry. Check Settings > Notifications > MealPrep Planner. |

## Support and privacy pages

The marketing page, support page and privacy policy are published with GitHub Pages from the `gh-pages` branch:

- https://junhao-fred.github.io/MealPrepPlanner/
- https://junhao-fred.github.io/MealPrepPlanner/support/
- https://junhao-fred.github.io/MealPrepPlanner/privacy/

## Independent verification record

A teammate should follow these instructions from a clean checkout on a Mac and add their outcome below. The developer run is recorded first.

- Reviewer / date: Junhao Huang, 25 October 2026 (developer run)
- Source reviewed: the submitted source archive, unzipped into an empty folder
- macOS / Xcode version and build: macOS 26.7.1 / Xcode 27.1 (27A9275)
- Simulator or device / iOS version: iPhone 17 Pro simulator / iOS 26.4
- Signing and identifier changes: none; simulator only
- Test summary: 181 tests in 31 suites passed; 0 build warnings
- Smoke check, persistence and widget outcome: deletion, missed meals, pantry grouping and the shopping list checked in the simulator; editing, stock deduction and undo covered by unit tests; widget on the Home Screen **Pending**
- VoiceOver, large text and dark mode outcome: dark mode checked; VoiceOver and large text **Pending**
- Problems found and follow-up: physical-device signing **Pending**
