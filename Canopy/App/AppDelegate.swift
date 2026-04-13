import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows — show the Welcome window
            for window in sender.windows {
                if window.identifier?.rawValue.contains("welcome") == true {
                    window.makeKeyAndOrderFront(nil)
                    return false
                }
            }
        }
        return true
    }

    @objc func showNewProjectSheet() {
        // Placeholder for File > New Project menu action
        // Opens the welcome window which hosts the new project sheet
        for window in NSApp.windows {
            if window.identifier?.rawValue.contains("welcome") == true {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
    }
}
