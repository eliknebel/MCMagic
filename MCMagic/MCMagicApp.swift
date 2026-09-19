//
//  MCMagicApp.swift
//  MCMagic
//
//  Created by Eli Knebel on 9/16/26.
//

import AppKit
import SwiftUI

@main
struct MCMagicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("MCMagic", systemImage: model.isEnabled ? "rectangle.3.group" : "rectangle.3.group.fill") {
            Button("Preferences…") {
                PreferencesWindowController.shared.show()
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit MCMagic") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let showPreferencesNotification = Notification.Name(
        "com.bitbldr.MCMagic.showPreferences"
    )
    private var isSecondaryInstance = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showPreferences),
            name: Self.showPreferencesNotification,
            object: nil
        )

        let otherInstances = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.bitbldr.MCMagic"
        ).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

        if let existingInstance = otherInstances.first {
            isSecondaryInstance = true
            DistributedNotificationCenter.default().post(
                name: Self.showPreferencesNotification,
                object: nil
            )
            existingInstance.activate(options: [.activateAllWindows])
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isSecondaryInstance else { return }
        AppModel.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PreferencesWindowController.shared.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func showPreferences() {
        PreferencesWindowController.shared.show()
    }
}
