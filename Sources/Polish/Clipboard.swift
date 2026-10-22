import AppKit

/// Reads and writes the frontmost app's selection by sending ⌘C / ⌘V, putting the user's clipboard back afterwards.
@MainActor
enum Clipboard {
    static func copySelection() async -> String? {
        await waitForModifierRelease()
        let pasteboard = NSPasteboard.general
        let saved = snapshot()
        let before = pasteboard.changeCount
        press(0x08) // kVK_ANSI_C
        let deadline = Date.now.addingTimeInterval(0.5)
        while pasteboard.changeCount == before, Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let text = pasteboard.changeCount == before ? nil : pasteboard.string(forType: .string)
        restore(saved)
        return text
    }

    static func paste(_ text: String) async {
        let saved = snapshot()
        set(text)
        let ours = NSPasteboard.general.changeCount
        press(0x09) // kVK_ANSI_V
        // A busy app reads the clipboard late; restoring too early would paste the user's old clipboard instead.
        try? await Task.sleep(for: .seconds(1))
        if NSPasteboard.general.changeCount == ours { restore(saved) } // don't clobber something the user copied meanwhile
    }

    static func set(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func snapshot() -> [NSPasteboardItem] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem]) {
        NSPasteboard.general.clearContents()
        if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
    }

    private static func press(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// The shortcut's ⌃⌥ may still be held; they'd turn our ⌘C into ⌃⌥⌘C.
    private static func waitForModifierRelease() async {
        let deadline = Date.now.addingTimeInterval(1)
        while !NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty, Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
