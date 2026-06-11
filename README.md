# ApplicationManager

A lightweight macOS menu bar app that keeps your personal utilities in one place. It automatically discovers `.app` bundles in the **Menu Bar Applications** folder (the parent directory of this project) and lets you launch them with one click.

## Features

- Menu bar only (no dock icon)
- Auto-discovers apps in `Menu Bar Applications/` and sibling project folders (e.g. `Caffeinated/build/Caffeinated.app`)
- One-click launch for apps in your library
- Running apps show a checkmark; click again to turn them off
- Add or remove apps from the menu
- Refresh Library to pick up newly built apps
- Manual additions stored as JSON in Application Support

## Requirements

- macOS 13.0 or later
- Apple developer tools (Command Line Tools or Xcode)

## Build

```bash
chmod +x build.sh
./build.sh
open "build/ApplicationManager.app"
```

## Install

```bash
cp -r "build/ApplicationManager.app" /Applications/
open /Applications/ApplicationManager.app
```

## Usage

| Action | Result |
|--------|--------|
| Click menu bar icon | Open your app library (refreshes discovery) |
| Click an app | Launch it (or quit if already running) |
| Refresh Library | Re-scan Menu Bar Applications folder |
| Add Application… | Pick a `.app` bundle to add manually |
| Manage Library… | Remove apps from the list |
| Reveal Menu Bar Applications Folder | Open the parent folder in Finder |

## How discovery works

The app looks for a folder named **Menu Bar Applications**:

1. Walks up from the running app bundle (works when launched from `build/ApplicationManager.app` inside the project)
2. Falls back to `~/Projects/Menu Bar Applications`

It then scans that folder for `.app` bundles, including inside sibling project folders (up to 5 levels deep), so paths like:

- `Menu Bar Applications/SomeApp.app`
- `Menu Bar Applications/Caffeinated/build/Caffeinated.app`
- `Menu Bar Applications/QuitAll/build/Build/Products/Release/QuitAll.app`

are found automatically. ApplicationManager excludes itself from the list.

Discovered apps are merged with your saved library on each menu open. Use **Refresh Library** after building a new app.

## Library config

Manual additions and removals are stored at:

```
~/Library/Application Support/com.applicationmanager.app/library.json
```

Previous config locations are migrated automatically on first launch.
