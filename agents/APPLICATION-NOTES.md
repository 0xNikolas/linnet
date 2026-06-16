# Application Technical Notes

Findings and patterns discovered during development and testing.

## Automated UI Testing Workflow

When fixing UI bugs that are hard to verify visually, use this workflow:

1. **Add a menu item** with a keyboard shortcut for the action being tested (e.g., `CommandGroup(after: .sidebar)` in `LinnetApp.swift`). This gives a reliable automation target.
2. **Write a shell test script** using `osascript` accessibility APIs:
   - **Toggle via menu:** `osascript -e 'tell application "System Events" to tell process "Linnet" to click menu item "Toggle Queue" of menu "View" of menu bar 1'`
   - **Check visibility:** `osascript -e 'tell application "System Events" to tell process "Linnet" to get entire contents of window 1' 2>&1 | grep -o "static text Queue" | wc -l | tr -d ' '`
   - **Set defaults before launch:** `defaults write com.linnet.app <key> -bool <true|false>`
3. **Test lifecycle:** kill app -> set defaults -> launch -> wait 4s -> check state -> toggle -> wait 2s -> check state
4. **Run tests iteratively** after each code change, only signal completion when all pass

## SwiftUI macOS Patterns

### Toolbar items inside NavigationStack

SwiftUI `.toolbar` items inside `NavigationStack` appear in the SwiftUI navigation bar area, **not** the macOS `NSToolbar`. They cannot be clicked via accessibility `buttons of toolbar 1`.

### @AppStorage re-render loops

`@AppStorage` in views with `.toolbar` buttons can cause re-render loops where the button action fires multiple times per click. Fix: use `NotificationCenter` to decouple the toggle action from the view's state. The view posts a notification, and a parent view (e.g., `ContentView`) listens and toggles the state.

### NavigationStack greedy layout in HStack

`NavigationStack` inside an `HStack` takes all available space and won't yield to sibling views added conditionally at runtime. Fix: add `.frame(maxWidth: .infinity)` to the `NavigationStack` so it flexes and yields space for siblings like a side panel.
