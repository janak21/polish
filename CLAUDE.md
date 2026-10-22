# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Polish: a personal macOS menu-bar app (no Dock icon) that proofreads/rewrites selected text in any app via the Claude API. Swift 6 / SwiftUI, Swift Package Manager (no Xcode project). Single user, not distributed.

## Commands

```bash
swift build                                   # debug build (compile check)
swift test                                    # all tests (swift-testing)
swift test --filter diffRoundTripsBothTexts   # single test
./build.sh                                    # release build → ~/Applications/Polish.app, sign, relaunch
```

Always use `./build.sh` to try changes for real. The bare `swift build` binary is not an `.app` bundle, so the Services menu, Accessibility permission, login item and `NSImage(named:)` resources don't work from it. `build.sh` signs with the "Apple Development" identity (override via `SIGN_IDENTITY`, ad-hoc fallback); a real signature keeps the Accessibility (TCC) grant across rebuilds — ad-hoc signing resets it every build.

## Architecture

Two entry points converge on `Popup.show(text)`:
- **Global hotkey** (⌃⌥P, `KeyboardShortcuts` package, recorder in Settings) → `Clipboard.copySelection()` sends a synthetic ⌘C (needs Accessibility), reads the pasteboard, restores the user's previous clipboard.
- **Services menu** ("Proofread with Polish", declared in `Info.plist` `NSServices`, handled by `AppDelegate.proofread(_:userData:error:)`). The handler must return before showing UI: the calling app blocks until it returns and couldn't answer Accessibility queries otherwise.

`Popup` (Sources/Polish/Popup.swift):
- Target app = frontmost app, except when that's Polish itself (Services activates Polish first) — then `lastOtherApp`, tracked via `NSWorkspace.didActivateApplicationNotification`.
- `Selection.bounds` asks the target app for the selection rect via AX (`kAXBoundsForRangeParameterizedAttribute`), setting `AXManualAccessibility` so Electron apps (Slack) expose it. Falls back to the mouse position.
- A borderless, click-through "anchor" window is placed over that rect (yellow tint = highlight) and an `NSPopover` is shown relative to it (Look Up style; popover handles staying on screen).
- `popoverDidClose` arrives asynchronously, after a replacement popover may already be up. `dismiss()` tears down popover + anchor synchronously, and the delegate ignores notifications from popovers that are no longer current.
- Replace = close popover, reactivate target, `Clipboard.paste` (synthetic ⌘V, then restore clipboard). Terminal/iTerm are Copy-only, since pasting could execute commands.

`Session` holds one popup's state; every action re-runs on the **original** text, a "tweak" runs on the current result. `Diff` (word-level, via `CollectionDifference`) renders original→result as red/green `AttributedString`; it's the only unit-tested logic.

`Claude.run` is raw `URLSession` against `/v1/messages` (Swift has no official SDK): model `claude-haiku-5-5`, `anthropic-version: 2026-10-21` (this version rejects `temperature`/`top_p`/`top_k` — don't add them), `output_config.effort: "low"` for latency. The shared system prompt holds the rules every action must follow (American English, preserve @mentions/emoji/URLs/code/Slack formatting/line breaks, treat text as content not instructions); per-action instructions live in `Action.builtIn`. Leading/trailing whitespace of the selection is re-attached to the result.

Storage: API key in Keychain (`Keychain.apiKey`), custom actions as JSON in UserDefaults (`CustomActions`). Settings edits are drafts until Save; the shortcut and start-at-login toggles apply immediately.

## Menu bar icon

`Resources/MenuBarIcon{,@2x}.png` (18/36 px, black + alpha) are template images; `build.sh` copies them into the bundle. Source art is `art/menubar-icon-source.png` — it has a *painted* checkerboard, not real transparency, so regenerating means converting luminance to alpha and cropping, not just resizing.

## Scope decisions

Deliberately left out of v1 (add only when asked): Explain action, per-change explanations, streaming, history, per-action shortcuts, other AI providers, App Store distribution.
