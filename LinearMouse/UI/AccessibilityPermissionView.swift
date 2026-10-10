// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct AccessibilityPermissionView: View {
    var eventTapFailed = false
    var permissionNaming = AccessibilityPermission.Naming.current

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .accessibility(hidden: true)
                .padding(.bottom, 24)

            explanation
                .font(.system(size: 15))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if permissionNaming.formerNameKey != nil, !eventTapFailed {
                permissionFootnote
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            primaryButton
                .padding(.top, 28)
            helpLink
                .font(.system(size: 15))
                .padding(.top, 16)
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var explanation: Text {
        if eventTapFailed {
            return Text(
                "LinearMouse could not start mouse input processing. Restart LinearMouse. If the problem persists, get more help."
            )
        }
        // Keep the sentence in one localization so each language controls its word order.
        let parts = NSLocalizedString(
            "LinearMouse needs %@ permission to customize scrolling, pointer movement, and mouse buttons.",
            comment: "%@ is the localized system permission name."
        ).components(separatedBy: "%@")
        let permission = Text(NSLocalizedString(permissionNaming.settingsPaneKey, comment: "")).bold()
        var marker = Text("")
        if permissionNaming.formerNameKey != nil {
            marker = Text("1").font(.system(size: 10)).baselineOffset(5)
        }
        return Text(parts[0]) + permission + marker + Text(parts.dropFirst().joined(separator: "%@"))
    }

    private var permissionFootnote: Text {
        let parts = NSLocalizedString(
            "Called %@ in earlier versions of macOS.",
            comment: "Footnote explaining the system permission name in earlier macOS versions."
        ).components(separatedBy: "%@")
        let formerName = NSLocalizedString(permissionNaming.formerNameKey ?? "Accessibility", comment: "")
        return Text("¹ " + parts[0]) + Text(formerName).bold()
            + Text(parts.dropFirst().joined(separator: "%@"))
    }

    private var actionButton: some View {
        Button(action: {
            if eventTapFailed {
                Application.restart()
            } else {
                AccessibilityPermissionWindow.shared.beginAuthorization()
            }
        }) {
            Text(LocalizedStringKey(eventTapFailed ? "Restart LinearMouse" : "Open Settings"))
                .font(.system(size: 15))
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var primaryButton: some View {
        if #available(macOS 26, *) {
            actionButton
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
        } else if #available(macOS 13, *) {
            actionButton
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        } else if #available(macOS 11, *) {
            actionButton.keyboardShortcut(.defaultAction)
        } else {
            actionButton
        }
    }

    private var helpLink: some View {
        HyperLink(URL(string: "https://go.linearmouse.app/accessibility-permission")!) {
            Text("Get more help")
        }
    }
}

struct AccessibilityPermissionView_Previews: PreviewProvider {
    static var previews: some View {
        AccessibilityPermissionView()
    }
}
