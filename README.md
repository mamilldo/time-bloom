# TimeBloom — macOS Menu Bar Time Tracker

A polished, Harvest-style menu bar app for macOS 14 (Sonoma) that talks to
the [TimeBloom Suite API](https://time-bloom-suite.lovable.app/api-docs).

The app lives **only** in the menu bar (no Dock icon), uses **SwiftUI** for its
popover UI, **AppKit** for the menu bar item, and **Swift Concurrency
(async/await)** for all networking. Tokens are stored exclusively in the
**Keychain**.

---

## 1. Environment Setup

You said Xcode and Homebrew are already installed. Here's everything else you
need.

### 1.1 Confirm versions

```bash
xcodebuild -version            # Xcode 15.x or newer
swift --version                # Swift 5.9+
sw_vers                        # macOS 14+ recommended for development
```

### 1.2 Optional but recommended dev tools

```bash
brew install swiftlint         # Inline lint warnings inside Xcode
brew install swiftformat       # Auto-format on save (optional)
brew install xcbeautify        # Pretty-prints xcodebuild output
```

None of these are required to ship the app — the project compiles with stock
Xcode alone.

### 1.3 Sign in to Xcode with an Apple ID

Even for local-only development, macOS requires the binary to be signed.

1. Open Xcode → **Settings…** → **Accounts**
2. Click **+** and add your Apple ID (a free account is fine)
3. Select the team — Xcode will use it to sign with a "Personal Team" cert.

---

## 2. Creating the Xcode Project

### 2.1 New project

1. **File → New → Project…**
2. Choose **macOS → App** → **Next**
3. Set:
   - **Product Name:** `TimeBloom`
   - **Team:** your personal team
   - **Organization Identifier:** e.g. `com.yourname`
   - **Bundle Identifier:** auto-generated, e.g. `com.yourname.TimeBloom`
   - **Interface:** **SwiftUI**
   - **Language:** **Swift**
   - **Storage:** **None**
   - **Include Tests:** unchecked (add later if you want)
4. Save it **inside this repo's `TimeBloom/` folder** so the existing source
   files line up with the project layout.

### 2.2 Replace the generated source with this repo's files

Xcode will create a stub `TimeBloomApp.swift` and `ContentView.swift`. Delete
both from the project navigator (move to trash), then drag the
`TimeBloom/` folders from this repository into the project navigator
(check **Copy items if needed** is **off**, **Create groups** is on, and the
TimeBloom target is selected).

The folders to add are:

```
TimeBloom/
├── TimeBloomApp.swift          # @main entry point
├── AppDelegate.swift           # NSApplicationDelegate, owns MenuBarController
├── Models/                     # Codable types from the API
├── Networking/                 # APIClient, endpoints, error types
├── Storage/                    # KeychainStore, AppSettings
├── Services/                   # AuthService, TimerStore, IdleMonitor, NotificationManager
├── UI/                         # SwiftUI views + the AppKit MenuBarController
└── Resources/                  # Info.plist additions, .entitlements
```

### 2.3 Project settings — make it a menu-bar-only app

In the **TimeBloom target → Info** tab, add a row:

| Key                                    | Type    | Value |
|----------------------------------------|---------|-------|
| `Application is agent (UIElement)`     | Boolean | `YES` |

The raw key is `LSUIElement`. Setting it to `YES` is what removes the Dock
icon and the app-menu entry. (`Resources/Info.plist` in this repo shows the
full plist if you'd rather inspect/copy a complete file.)

While you're in **Signing & Capabilities**:

1. Verify **Signing** uses your team and **Automatically manage signing** is on.
2. Click **+ Capability** and add **App Sandbox**.
3. Under App Sandbox check:
   - **Network → Outgoing Connections (Client)** — needed for HTTPS calls.
   - Leave file system / hardware boxes unchecked.
4. Click **+ Capability** again and add **Hardened Runtime** (Xcode often
   adds it automatically; verify it's present).

The matching `TimeBloom.entitlements` is in `Resources/`.

### 2.4 Deployment target

In **TimeBloom target → General → Minimum Deployments**, set **macOS** to
**14.0**. We use `MenuBarExtra` and `Observable` features that are clean on
14+.

### 2.5 Accent color & assets

Open `Assets.xcassets`:

- **AccentColor**: set the "Any Appearance" swatch to `#1F6739` (TimeBloom
  dark green) and the "Dark" swatch to `#3FA86A` (a brighter shade so it
  remains legible on dark backgrounds). The `AccentColor.colorset/Contents.json`
  in this repo already has these values.
- **AppIcon**: drop in any 1024×1024 PNG; for now Xcode will warn but build.

The brand color is also exposed programmatically as `Theme.brandGreen` in
`UI/Theme.swift`.

---

## 3. Configuring the API base URL

Open `Networking/Endpoints.swift` and edit:

```swift
enum Endpoints {
    /// Set this once. All requests are built relative to it.
    static let baseURL = URL(string: "https://time-bloom-suite.lovable.app")!
    ...
}
```

If/when the real API spec at `https://time-bloom-suite.lovable.app/api-docs`
uses different paths or response keys, update **only this one file** plus the
matching `Codable` model. Every endpoint is centralized; views and services
never hard-code URLs.

The default endpoints assumed in this project (adjust as needed):

| Action               | Method | Path                            |
|----------------------|--------|---------------------------------|
| Login                | POST   | `/api/auth/login`               |
| Current user         | GET    | `/api/auth/me`                  |
| List projects        | GET    | `/api/projects`                 |
| List tasks           | GET    | `/api/tasks`                    |
| Active timer         | GET    | `/api/time-entries/active`      |
| Start timer          | POST   | `/api/time-entries`             |
| Stop timer           | POST   | `/api/time-entries/:id/stop`    |
| Update entry         | PATCH  | `/api/time-entries/:id`         |
| Discard entry        | DELETE | `/api/time-entries/:id`         |

---

## 4. Running & testing locally

### 4.1 Run

Hit **⌘R** in Xcode. The app launches with no Dock icon — look at the right
side of your menu bar for a small bloom/timer glyph. Click it to open the
popover.

### 4.2 Quitting

There's a **Quit** button in the popover. You can also right-click the menu
bar icon for the secondary menu (Quit, Preferences).

### 4.3 Test each feature

| Feature              | How to verify                                                               |
|----------------------|-----------------------------------------------------------------------------|
| Login                | First launch shows `LoginView`; success transitions to the timer popover.   |
| Token persistence    | Quit & relaunch — should jump straight to the timer view.                   |
| Start/Stop           | Pick a project + task, click **Start**. Icon switches to the "running" glyph; menu bar title shows elapsed time. |
| Switch tasks         | While running, choose a different task — the previous entry stops and a new one starts. |
| Idle detection       | Set the threshold to `1 minute` in Preferences, leave the keyboard alone, and confirm the dialog appears. |
| Long-running timer   | Temporarily change `LongRunningTimerThreshold` to `60` seconds in `TimerStore.swift`, start a timer, wait. |
| Notifications        | First run, grant the permission prompt. Trigger idle as above to see an actionable banner. |
| Error handling       | Toggle airplane mode, click Start — you should see a friendly inline error. |

### 4.4 Reset the Keychain entry while developing

```bash
security delete-generic-password -s "com.yourname.TimeBloom.token" 2>/dev/null
```

Replace the `-s` value with whatever bundle id you used.

---

## 5. UX & technical enhancements worth adding next

These are intentionally **out of scope for v1** but would make the app great:

- **Global hotkey** (⌃⇧Space) to start/stop the last task without opening the
  popover — use `MASShortcut` or a tiny hand-rolled `NSEvent.addGlobalMonitor`.
- **Recent tasks list** at the top of the picker for one-click resume.
- **Project search/fuzzy match** in the picker (`SwiftUI.searchable`).
- **Calendar awareness**: read EventKit, surface "starting meeting in 5 min —
  switch to project X?" prompts.
- **Pomodoro-style focus timers** layered on top of the time entry.
- **Login-item helper**: `SMAppService.mainApp.register()` so it launches at
  login.
- **Sparkle** for auto-updates if you distribute outside the App Store.
- **Live Activities / Dynamic Island** parity on iOS via shared package if
  you ever ship a companion phone app.
- **Offline queue**: keep timer changes locally if the network drops, replay
  on reconnect.
- **Watch glance**: a tiny watchOS complication showing the running timer.
- **Local-first DB** (GRDB / SwiftData) for time entries with API as truth.
- **VoiceOver pass + larger-type tests** before shipping.

---

## 6. Where each file lives & why

```
TimeBloom/
├── TimeBloomApp.swift                 SwiftUI @main; wires AppDelegate; no WindowGroup.
├── AppDelegate.swift                  Owns MenuBarController; runs setup at launch.
├── Models/Models.swift                Codable structs for User, Project, Task, TimeEntry.
├── Networking/
│   ├── APIClient.swift                Generic, async/await HTTP client; injects Bearer token.
│   ├── Endpoints.swift                Single source of truth for URLs and request bodies.
│   └── APIError.swift                 Typed errors with user-friendly localized strings.
├── Storage/
│   ├── KeychainStore.swift            Tiny wrapper over the Security framework. Tokens only.
│   └── AppSettings.swift              UserDefaults-backed preferences (idle threshold etc.).
├── Services/
│   ├── AuthService.swift              Login, logout, "are we authed?" — owns the token.
│   ├── TimerStore.swift               @MainActor @Observable; the app's source of truth.
│   ├── IdleMonitor.swift              Polls CGEventSource for system idle; emits events.
│   └── NotificationManager.swift      UNUserNotificationCenter, categories, action handlers.
├── UI/
│   ├── MenuBarController.swift        AppKit NSStatusItem + NSPopover + SwiftUI hosting.
│   ├── PopoverRootView.swift          Routes between LoginView and TimerView.
│   ├── LoginView.swift                Email/password form, calls AuthService.
│   ├── TimerView.swift                Status, start/stop, switch task button.
│   ├── TaskPickerView.swift           Project → task drilldown.
│   ├── IdleResolutionView.swift       The "you were away X minutes" sheet.
│   └── Theme.swift                    Brand color tokens + small style helpers.
└── Resources/
    ├── Info.plist                     LSUIElement = YES, NSAppTransportSecurity, etc.
    └── TimeBloom.entitlements         App Sandbox + outgoing network.
```
