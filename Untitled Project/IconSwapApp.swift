import SwiftUI
import AppKit

struct IconSwapApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(CompactWindowSizer())
        }
        .defaultSize(width: CompactWindowSizer.size.width, height: CompactWindowSizer.size.height)
    }
}

/// Forces the window to a compact, centered frame every time it opens,
/// overriding whatever frame macOS restored from the previous session.
private struct CompactWindowSizer: NSViewRepresentable {
    static let size = CGSize(width: 900, height: 600)

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The window isn't attached yet during makeNSView; wait one runloop turn.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            // Never exceed the screen, even on very small displays.
            let width = min(Self.size.width, visible.width)
            let height = min(Self.size.height, visible.height)
            window.setContentSize(NSSize(width: width, height: height))
            window.center()
            context.coordinator.observe(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// SwiftUI grows the window whenever the content's minimum size grows
    /// (a long error message, a new banner…). This pulls it back inside the
    /// visible screen area whenever that happens.
    final class Coordinator {
        private var observer: NSObjectProtocol?

        func observe(_ window: NSWindow) {
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                guard let window else { return }
                MainActor.assumeIsolated { Self.clamp(window) }
            }
        }

        @MainActor
        private static func clamp(_ window: NSWindow) {
            guard let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
            var frame = window.frame
            guard frame.width > visible.width || frame.height > visible.height
                    || !visible.contains(frame) else { return }
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
            guard frame != window.frame else { return }
            window.setFrame(frame, display: true)
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
