//
//  AccessibilityPermissionView.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/9.
//

import SwiftUI
import os.log

struct AccessibilityPermissionView: View {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AccessibilityPermissionView")

    @State var resetAllPermissionConfirmationShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 15) {
                Image("AccessibilityIcon")
                    .resizable()
                    .frame(width: 40, height: 40)

                Text("LinearMouse needs Accessibility permission")
                    .font(.headline)
            }
            .padding(.horizontal)


            Text("You need to grant Accessibility permission in System Preferences > Security & Pravicy > Accessibility.")
                .padding(.horizontal)

            HyperLink(URL(string: "https://go.linearmouse.org/accessibility-permission")!) {
                Text("Get more help")
            }
            .padding(.horizontal)

            Spacer()

            HStack {
                Button("Open Accessibility") {
                    openAccessibility()
                }

                Spacer()

                Button("Reset all permissions...") {
                    resetAllPermissions()
                }
            }
        }
        .padding()
        .frame(width: 450, height: 200)
    }

    func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)

        StatusItem.shared.moveAccessibilityWindowToTheTop()
    }

    func resetAllPermissions() {
        let alert = NSAlert()

        alert.messageText = NSLocalizedString("Are you sure?", comment: "")
        alert.informativeText = NSLocalizedString("This will reset all granted Accessibility permissions in the system.", comment: "")
        alert.alertStyle = .warning

        let reset = alert.addButton(withTitle: NSLocalizedString("Reset", comment: ""))
        reset.keyEquivalent = ""

        let cancel = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancel.keyEquivalent = "\r"

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let command = "do shell script \"tccutil reset Accessibility\" with administrator privileges"

        guard let script = NSAppleScript(source: command) else {
            os_log("Failed to reset Accessibility permissions", log: Self.log, type: .error)
            return
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard error == nil else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        AccessibilityPermission.prompt()
    }
}

struct AccessibilityPermissionView_Previews: PreviewProvider {
    static var previews: some View {
        AccessibilityPermissionView()
    }
}
