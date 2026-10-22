# Polish

Proofread or rewrite selected text in any macOS app with Claude, without copy-pasting into a chat window.

Select text, press **⌃⌥P** (or right-click → Services → **Proofread with Polish**). A popover appears next to the selection with the corrected text and the changes highlighted. Press **⏎** to replace the selection, **⌘C** to copy, or **Esc** to close.

Built-in actions: Proofread, Improve, Rewrite, Casual, Formal. Add your own (a name plus an instruction) in Settings. Type a follow-up like "shorter" in the popover to tweak the result.

## Requirements

- macOS 15 or later
- Xcode 16+ (Swift 6 toolchain)
- A [Claude API key](https://console.anthropic.com/settings/keys)

## Build and run

```bash
./build.sh
```

This builds a release binary, wraps it into `~/Applications/Polish.app`, signs it and launches it. Polish lives in the menu bar and starts at login (toggle in Settings).

Then:
1. Menu bar icon → **Settings…** → paste your API key → **Save**.
2. Press ⌃⌥P on some selected text and allow Polish under System Settings → Privacy & Security → **Accessibility**. Polish needs this to copy your selection, paste the result and find where the selection is on screen.

`build.sh` signs with your "Apple Development" certificate if you have one (override with `SIGN_IDENTITY=...`), otherwise ad-hoc. With an ad-hoc signature macOS forgets the Accessibility permission on every rebuild.

```bash
swift test   # unit tests
```

## Notes

- Selected text is sent to the Anthropic API (`claude-haiku-5-5`). Your API key is stored in the macOS Keychain.
- The shortcut copies the selection by sending ⌘C and restores your previous clipboard afterwards.
- In Terminal and iTerm, Polish offers Copy only, because pasting into a shell could run the text as a command.
- If an app doesn't report where the selection is, the popover points at the mouse instead.

## License

MIT, see [LICENSE](LICENSE).
