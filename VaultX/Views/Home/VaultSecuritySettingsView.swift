import SwiftUI

struct VaultSecuritySettingsView: View {
    @EnvironmentObject private var settings: VaultSecuritySettings
    @EnvironmentObject private var appState: AppLockState
    @State private var faceIDAlert: FaceIDSettingsAlert?
    @State private var isVerifyingFaceIDDisable = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: faceIDBinding) {
                    settingsLabel(
                        title: "استخدام Face ID",
                        subtitle: isVerifyingFaceIDDisable
                            ? "جاري التحقق من هويتك..."
                            : "فتح VaultX باستخدام بصمة الوجه",
                        systemImage: "faceid"
                    )
                }
                .disabled(isVerifyingFaceIDDisable)

                Picker(selection: $settings.autoLockDelay) {
                    ForEach(AutoLockDelay.allCases) { delay in
                        Text(delay.displayName).tag(delay)
                    }
                } label: {
                    settingsLabel(
                        title: "القفل التلقائي",
                        subtitle: settings.autoLockDelay.displayName,
                        systemImage: "lock.rotation"
                    )
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("القفل والحماية")
            } footer: {
                Text("عند اختيار مدة مؤجلة، تبقى معاينة VaultX مخفية في مبدّل التطبيقات، ويُطلب فتح الخزنة بعد انقضاء المدة.")
            }

            Section {
                Picker(selection: $settings.clipboardClearDelay) {
                    ForEach(ClipboardClearDelay.allCases) { delay in
                        Text(delay.displayName).tag(delay)
                    }
                } label: {
                    settingsLabel(
                        title: "مسح الحافظة",
                        subtitle: settings.clipboardClearDelay.displayName,
                        systemImage: "doc.on.clipboard"
                    )
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("الحافظة")
            } footer: {
                Text("تنتهي صلاحية كلمات المرور ورموز التحقق التي ينسخها VaultX تلقائيًا، ولا تُرسل إلى الحافظة العامة بين أجهزة Apple.")
            }

            Section {
                Toggle(isOn: $settings.hideTOTPCodesByDefault) {
                    settingsLabel(
                        title: "إخفاء رموز التحقق افتراضيًا",
                        subtitle: "إظهار الرمز فقط عند الضغط على زر العين",
                        systemImage: "eye.slash"
                    )
                }
            } header: {
                Text("رموز التحقق")
            } footer: {
                Text("تُخفى الرموز المكشوفة مجددًا عند مغادرة التطبيق أو قفل الخزنة.")
            }

            Section("حالة الأمان") {
                statusRow(
                    title: "Face ID",
                    value: settings.isFaceIDEnabled ? "مفعّل" : "غير مفعّل",
                    systemImage: "faceid"
                )
                statusRow(
                    title: "القفل التلقائي",
                    value: settings.autoLockDelay.displayName,
                    systemImage: "lock.fill"
                )
                statusRow(
                    title: "مسح الحافظة",
                    value: settings.clipboardClearDelay.displayName,
                    systemImage: "clipboard.fill"
                )
                statusRow(
                    title: "التخزين المشفر",
                    value: "مفعّل",
                    systemImage: "externaldrive.fill.badge.checkmark"
                )
                statusRow(
                    title: "الاتصال بالإنترنت",
                    value: "غير مستخدم",
                    systemImage: "wifi.slash"
                )
            }
        }
        .navigationTitle("الإعدادات والأمان")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .alert(item: $faceIDAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("حسنًا"))
            )
        }
    }

    private var faceIDBinding: Binding<Bool> {
        Binding(
            get: { settings.isFaceIDEnabled },
            set: { newValue in
                guard newValue != settings.isFaceIDEnabled else { return }

                if newValue {
                    guard appState.biometricService.canEvaluateFaceID() else {
                        faceIDAlert = .unavailable
                        return
                    }
                    settings.isFaceIDEnabled = true
                    return
                }

                guard !isVerifyingFaceIDDisable else { return }
                isVerifyingFaceIDDisable = true

                appState.verifyOwnerWithFaceID(
                    reason: "تحقق من هويتك لإيقاف Face ID في VaultX"
                ) { result in
                    isVerifyingFaceIDDisable = false

                    switch result {
                    case .success:
                        settings.isFaceIDEnabled = false
                    case .cancelled:
                        break
                    case .authenticationFailed:
                        faceIDAlert = .verificationFailed
                    case .lockedOut:
                        faceIDAlert = .lockedOut
                    case .notEnrolled, .notAvailable:
                        faceIDAlert = .unavailable
                    }
                }
            }
        )
    }

    private func settingsLabel(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 30)

            VStack(alignment: .trailing, spacing: 3) {
                Text(title)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func statusRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundColor(.primary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
    }
}

private enum FaceIDSettingsAlert: Identifiable {
    case unavailable
    case verificationFailed
    case lockedOut

    var id: String {
        switch self {
        case .unavailable: return "unavailable"
        case .verificationFailed: return "verificationFailed"
        case .lockedOut: return "lockedOut"
        }
    }

    var title: String {
        switch self {
        case .unavailable:
            return "Face ID غير متاح"
        case .verificationFailed:
            return "لم يتم إيقاف Face ID"
        case .lockedOut:
            return "Face ID مقفل مؤقتًا"
        }
    }

    var message: String {
        switch self {
        case .unavailable:
            return "تأكد من إعداد Face ID في الآيفون ثم حاول مرة أخرى."
        case .verificationFailed:
            return "لم ينجح التحقق من هويتك، لذلك بقي Face ID مفعّلًا."
        case .lockedOut:
            return "أعد تفعيل Face ID من خلال فتح الآيفون، ثم حاول مرة أخرى."
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        VaultSecuritySettingsView()
            .environmentObject(VaultSecuritySettings())
            .environmentObject(AppLockState.preview(state: .unlocked))
    }
}
#endif
