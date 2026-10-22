import KeyboardShortcuts
import ServiceManagement
import SwiftUI

extension KeyboardShortcuts.Name {
    static let proofread = Self("proofread", default: .init(.p, modifiers: [.control, .option]))
}

@main
struct PolishApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            SettingsButton()
            StatsMenu()
            Divider()
            Button("Quit Polish") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: menuBarIcon).accessibilityLabel("Polish")
        }
        Settings { SettingsView() }
    }

    /// Template image, so macOS tints it for light/dark menu bars like the system icons.
    private var menuBarIcon: NSImage {
        let image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: nil)!
        image.isTemplate = true
        return image
    }
}

private struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
    }
}

private struct StatsMenu: View {
    private let stats = Stats.shared

    var body: some View {
        let totals = stats.totals
        // No-op buttons, not Text: macOS greys out plain text in menus as disabled items.
        Menu("Stats") {
            Button("Claude Haiku: \(totals.claude.requests) requests, \((totals.claude.inputTokens + totals.claude.outputTokens).formatted()) tokens") {}
            Button("Estimated cost: \(totals.claude.cost.formatted(.currency(code: "USD").precision(.fractionLength(4))))") {}
            Button("On-device: \(totals.onDevice.requests) requests (free)") {}
            Divider()
            Button("Since \(totals.since.formatted(date: .abbreviated, time: .omitted))") {}
            Button("Reset Stats") { stats.reset() }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// A second press mid-copy would snapshot our copied selection as "the user's clipboard" and restore that instead.
    private var copying = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        Popup.trackFrontmostApp()

        KeyboardShortcuts.onKeyDown(for: .proofread) { [self] in
            Task { @MainActor in
                // Sending ⌘C to another app needs Accessibility permission; this shows the system prompt once.
                guard !copying, AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else { return }
                copying = true
                defer { copying = false }
                Popup.show(await Clipboard.copySelection())
            }
        }

        if !UserDefaults.standard.bool(forKey: "didRegisterLoginItem") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didRegisterLoginItem")
        }
    }

    /// Services menu entry point, declared as NSMessage "proofread" in Info.plist.
    @objc func proofread(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let text = pboard.string(forType: .string)
        // The calling app waits for this method to return; return first so it can answer our Accessibility queries.
        Task { @MainActor in Popup.show(text) }
    }
}
