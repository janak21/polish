import AppKit
import SwiftUI

@MainActor @Observable
final class Session {
    let original: String
    var result: String?
    var model: String? // which model produced `result`
    var diff: AttributedString? // original → `result`, computed once per result rather than on every redraw
    var changes = 0
    var error: String?
    var busy = false
    var tweak = ""

    init(original: String) {
        self.original = original
        if original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "Select some text first."
        } else {
            run(Action.builtIn[0])
        }
    }

    func run(_ action: Action) { run(action.instruction, on: original) }

    func applyTweak() {
        guard let result, !tweak.isEmpty else { return }
        run(tweak, on: result)
        tweak = ""
    }

    private func run(_ instruction: String, on text: String) {
        busy = true
        error = nil
        let original = original
        // Detached so the request goes out now, not after the main actor finishes building and laying out the popup,
        // and so diffing a long result doesn't stall the main thread.
        let request = Task.detached {
            let (result, model) = try await Claude.run(instruction, on: text)
            let parts = Diff.parts(from: original, to: result)
            return (result, model, Diff.attributed(parts), Diff.changeCount(parts))
        }
        Task {
            do { (result, model, diff, changes) = try await request.value } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

/// A Look Up–style popover pointing at the selected text, which gets a yellow highlight.
@MainActor
enum Popup {
    private static var popover: NSPopover?
    private static var anchor: NSWindow?
    private static var target: NSRunningApplication?
    private static let delegate = PopoverDelegate()
    // Pasting into a terminal could run the text as a command, so these get Copy only.
    private static let copyOnlyApps: Set = ["com.apple.Terminal", "com.googlecode.iterm2"]
    /// The Services menu brings Polish to the front before calling us, so remember the app the user was really in.
    private static var lastOtherApp: NSRunningApplication?

    static func trackFrontmostApp() {
        lastOtherApp = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier,
                  pid != getpid() else { return }
            MainActor.assumeIsolated { lastOtherApp = NSRunningApplication(processIdentifier: pid) }
        }
    }

    static func show(_ text: String?) {
        let session = Session(original: text ?? "") // first, so the request runs while the old popup closes and the new one is set up
        dismiss()
        let frontmost = NSWorkspace.shared.frontmostApplication
        target = frontmost == NSRunningApplication.current ? lastOtherApp : frontmost
        let canReplace = !copyOnlyApps.contains(target?.bundleIdentifier ?? "")
        let selection = target.flatMap(Selection.bounds)

        let view = PopupView(
            session: session,
            actions: Action.builtIn + CustomActions.shared.usable,
            canReplace: canReplace,
            close: { close() },
            copy: { Clipboard.set($0); close() },
            replace: { replace(with: $0) }
        )
        // An invisible window over the selection (or the mouse, if the app won't say where the selection is)
        // gives the popover something to point at, and draws the highlight.
        let mouse = NSEvent.mouseLocation
        let anchor = NSWindow(
            contentRect: selection ?? NSRect(x: mouse.x - 1, y: mouse.y - 1, width: 2, height: 2),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        anchor.isOpaque = false
        anchor.backgroundColor = selection == nil ? .clear : .systemYellow.withAlphaComponent(0.3)
        anchor.ignoresMouseEvents = true
        anchor.level = .floating
        anchor.isReleasedWhenClosed = false
        anchor.orderFront(nil)
        self.anchor = anchor

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = PopupView.size
        popover.contentViewController = NSHostingController(rootView: view)
        popover.delegate = delegate
        self.popover = popover

        NSApp.activate()
        popover.show(relativeTo: anchor.contentView!.bounds, of: anchor.contentView!, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private static func close() {
        dismiss()
        target?.activate()
    }

    /// Removes the popover and its anchor right away; the popover's own close notification arrives later.
    private static func dismiss() {
        popover?.close()
        if let anchor {
            // Fade the highlight out alongside the popover's own fade instead of vanishing ahead of it.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                anchor.animator().alphaValue = 0
            }
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                anchor.orderOut(nil)
            }
        }
        anchor = nil // cleared now, not after the fade, so a popup opened meanwhile keeps its own anchor
        popover = nil
    }

    private final class PopoverDelegate: NSObject, NSPopoverDelegate {
        /// Also fires after a click outside the popover. Ignore it for a popover that was already replaced.
        func popoverDidClose(_ notification: Notification) {
            if notification.object as? NSPopover === Popup.popover { Popup.dismiss() }
        }
    }

    private static func replace(with text: String) {
        close()
        // Without Accessibility permission the ⌘V would silently do nothing; leave the result on the clipboard instead.
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else {
            Clipboard.set(text)
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(150)) // let the target app take focus back
            await Clipboard.paste(text)
        }
    }
}

/// Where the selected text is on screen, asked of the app through the Accessibility API.
@MainActor
enum Selection {
    static func bounds(in app: NSRunningApplication) -> NSRect? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.3) // don't hang on a busy app
        // Electron/Chromium apps (Slack) only build their accessibility tree once asked to.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFBoolean)

        guard let focused: AXUIElement = value(of: appElement, kAXFocusedUIElementAttribute),
              let range: AXValue = value(of: focused, kAXSelectedTextRangeAttribute) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(focused, kAXBoundsForRangeParameterizedAttribute as CFString, range, &result) == .success,
              let boundsValue = result, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        // Accessibility rects have a top-left origin on the main screen; AppKit's is bottom-left.
        rect.origin.y = NSScreen.screens[0].frame.height - rect.maxY
        // A long selection can reach past the screen; keep the visible part so the popover stays on screen.
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) else { return nil }
        let visible = rect.intersection(screen.visibleFrame)
        return visible.isEmpty ? nil : visible
    }

    private static func value<T>(of element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

/// Apple Intelligence–style colored glow running around the popup's edge while waiting for a result.
private struct WaitingGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let colors: [Color] = [.blue, .purple, .pink, .orange, .yellow, .cyan, .blue]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3 // one lap per 3s
            let gradient = AngularGradient(colors: Self.colors, center: .center, angle: .degrees(turn * 360))
            let edge = RoundedRectangle(cornerRadius: 16, style: .continuous)
            ZStack {
                edge.strokeBorder(gradient, lineWidth: 8).blur(radius: 8)
                edge.strokeBorder(gradient, lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

struct PopupView: View {
    static let size = NSSize(width: 480, height: 300)

    @Bindable var session: Session
    let actions: [Action]
    let canReplace: Bool
    let close: () -> Void
    let copy: (String) -> Void
    let replace: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(actions) { action in
                        Button(action.name) { session.run(action) }
                    }
                }
            }
            .disabled(session.busy || session.original.isEmpty)

            ScrollView {
                Group {
                    if session.busy {
                        ProgressView().frame(maxWidth: .infinity).transition(.opacity)
                    } else if let error = session.error {
                        Text(error).foregroundStyle(.red).transition(.opacity)
                    } else if let diff = session.diff {
                        let changes = session.changes
                        VStack(alignment: .leading, spacing: 6) {
                            // Always say how many edits there are: a single added period is easy to miss in the text.
                            if changes == 0 {
                                Label("Looks good. No changes needed.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Label("\(changes) change\(changes == 1 ? "" : "s") highlighted below", systemImage: "pencil.circle.fill").foregroundStyle(.orange)
                            }
                            Text(diff)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
            }
            .background(.background.secondary, in: .rect(cornerRadius: 6))

            TextField("Tweak it, e.g. \"shorter\" — or press ⏎ to \(canReplace ? "replace" : "copy")", text: $session.tweak)
                .onSubmit { session.tweak.isEmpty ? primary() : session.applyTweak() }
                .disabled(session.result == nil || session.busy)

            HStack {
                if let model = session.model, session.result != nil, !session.busy {
                    Label(model, systemImage: model.hasPrefix("Claude") ? "cloud" : "laptopcomputer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close", action: close).keyboardShortcut(.cancelAction)
                Group {
                    if canReplace {
                        Button("Copy") { session.result.map(copy) }.keyboardShortcut("c")
                        Button("Replace") { primary() }.keyboardShortcut(.defaultAction)
                    } else {
                        Button("Copy") { primary() }.keyboardShortcut(.defaultAction)
                    }
                }
                .disabled(session.result == nil || session.busy)
            }
        }
        .padding(14)
        .frame(width: Self.size.width, height: Self.size.height)
        .overlay {
            if session.busy { WaitingGlow().transition(.opacity) }
        }
        // Opacity-only crossfade between spinner and result: no movement in text that's about to be read.
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.15), value: session.busy)
    }

    private func primary() {
        guard let result = session.result, !session.busy else { return }
        canReplace ? replace(result) : copy(result)
    }
}
