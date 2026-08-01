import SwiftUI

struct VaultSecuritySettingsView: View {
    @EnvironmentObject private var settings: VaultSecuritySettings
    @EnvironmentObject private var appState: AppLockState
    @State private var isShowingFaceIDUnavailableAlert = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: faceIDBinding) {
                    settingsLabel(
                        title: "استخدام Face ID",
                        subtitle: "فتح VaultX باستخدام بصمة الوجه",
                        systemImage: "faceid"
                    )
                }

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
        .alert("Face ID غير متاح", isPresented: $isShowingFaceIDUnavailableAlert) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text("تأكد من إعداد Face ID في الآيفون ثم حاول مرة أخرى.")
        }
    }

    private var faceIDBinding: Binding<Bool> {
        Binding(
            get: { settings.isFaceIDEnabled },
            set: { newValue in
                if newValue && !appState.biometricService.canEvaluateFaceID() {
                    isShowingFaceIDUnavailableAlert = true
                    settings.isFaceIDEnabled = false
                } else {
                    settings.isFaceIDEnabled = newValue
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

#if DEBUG
#Preview {
    NavigationStack {
        VaultSecuritySettingsView()
            .environmentObject(VaultSecuritySettings())
            .environmentObject(AppLockState.preview(state: .unlocked))
    }
}
#endif
