import SwiftUI
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    var hideMinimize: Bool = false
    var hideZoom: Bool = false
    var resizable: Bool = true
    var minSize: NSSize? = nil
    var maxSize: NSSize? = nil
    var transparentTitlebar: Bool = true

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(view: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(view: nsView) }
    }

    private func apply(view: NSView) {
        guard let win = view.window else { return }
        win.standardWindowButton(.miniaturizeButton)?.isHidden = hideMinimize
        win.standardWindowButton(.zoomButton)?.isHidden = hideZoom
        if resizable {
            win.styleMask.insert(.resizable)
        } else {
            win.styleMask.remove(.resizable)
        }
        if transparentTitlebar {
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.styleMask.insert(.fullSizeContentView)
            win.isMovableByWindowBackground = true
        } else {
            win.titlebarAppearsTransparent = false
            win.titleVisibility = .visible
        }
        if let minSize {
            win.minSize = minSize
        }
        if let maxSize {
            win.maxSize = maxSize
        } else {
            win.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                 height: CGFloat.greatestFiniteMagnitude)
        }
        // If min == max, lock window to that exact content size.
        if let m = minSize, let x = maxSize, m == x {
            if win.contentRect(forFrameRect: win.frame).size != m {
                win.setContentSize(m)
                if let screen = win.screen {
                    let origin = NSPoint(
                        x: screen.visibleFrame.midX - win.frame.width / 2,
                        y: screen.visibleFrame.midY - win.frame.height / 2
                    )
                    win.setFrameOrigin(origin)
                }
            }
        }
    }
}
