import SwiftUI

struct VaultMainMenuView: View {
    let onClose: () -> Void
    let onGoogleAuthenticatorImport: () -> Void
    let onBackupRestore: () -> Void
    let onSecuritySettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("VaultX")
                    .font(.title2.bold())
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 38, height: 38)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("إغلاق القائمة")
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 20)

            menuButton(
                title: "استيراد من Google Authenticator",
                systemImage: "square.and.arrow.down",
                action: onGoogleAuthenticatorImport
            )

            menuButton(
                title: "النسخ الاحتياطي والاستعادة",
                systemImage: "externaldrive.fill.badge.timemachine",
                action: onBackupRestore
            )

            menuButton(
                title: "الإعدادات والأمان",
                systemImage: "gearshape.fill",
                action: onSecuritySettings
            )

            Spacer(minLength: 0)

            Text(versionText)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 18)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func menuButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 11))

                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .environment(\.layoutDirection, .leftToRight)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "الإصدار \(version) (\(build))"
    }
}

#if DEBUG
#Preview {
    VaultMainMenuView(
        onClose: {},
        onGoogleAuthenticatorImport: {},
        onBackupRestore: {},
        onSecuritySettings: {}
    )
    .frame(width: 340)
    .preferredColorScheme(.dark)
}
#endif
