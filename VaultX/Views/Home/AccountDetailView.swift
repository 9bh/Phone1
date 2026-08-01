import SwiftUI
import UIKit

enum CopiedField: Hashable {
    case siteURL
    case email
    case username
    case password
    case notes
    case twoFA
}

struct AccountDetailView: View {
    let account: VaultAccount

    @EnvironmentObject private var settings: VaultSecuritySettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPasswordVisible = false
    @State private var copiedField: CopiedField? = nil
    @State private var isTOTPSecretVisible = false
    @State private var isTOTPCodeRevealed = false
    @ObservedObject private var clock = TOTPClock.shared
    
    private var currentTOTP: TOTPCode? {
        guard account.has2FA,
              let secretString = account.totpSecret,
              let secretData = try? Base32Decoder.decode(secretString) else {
            return nil
        }
        let config = TOTPConfiguration(
            secret: secretData,
            algorithm: account.totpAlgorithm,
            digits: account.totpDigits,
            period: account.totpPeriod
        )
        return try? TOTPEngine().generate(configuration: config, at: clock.currentTime)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Input Fields Group
                VStack(spacing: 16) {
                    if !account.siteURL.isEmpty {
                        detailRow(label: "رابط الموقع", value: account.siteURL, field: .siteURL)
                    }
                    if !account.email.isEmpty {
                        detailRow(label: "الإيميل", value: account.email, field: .email)
                    }
                    if !account.username.isEmpty {
                        detailRow(label: "اسم المستخدم", value: account.username, field: .username)
                    }
                    if !account.password.isEmpty {
                        passwordRow()
                    }
                }
                
                // 2FA Section
                if account.has2FA {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("التحقق بخطوتين (2FA)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "shield.checkerboard")
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 28))
                                
                                Spacer()
                                
                                if let totp = currentTOTP {
                                    Text(displayedTOTPCode(totp.value))
                                        .font(.system(size: 28, weight: .regular, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                        .monospacedDigit()
                                        .privacySensitive()
                                        .layoutPriority(1)
                                        .animation(.easeInOut(duration: 0.18), value: shouldMaskTOTPCode)

                                    Spacer()

                                    if settings.hideTOTPCodesByDefault {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                isTOTPCodeRevealed.toggle()
                                            }
                                        } label: {
                                            Image(systemName: isTOTPCodeRevealed ? "eye.slash" : "eye")
                                                .font(.system(size: 20))
                                                .foregroundColor(.primary)
                                                .frame(width: 44, height: 44)
                                                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                                .cornerRadius(10)
                                        }
                                        .accessibilityLabel(isTOTPCodeRevealed ? "إخفاء رمز التحقق" : "إظهار رمز التحقق")
                                    }

                                    Button(action: {
                                        copyToClipboard(totp.value, field: .twoFA)
                                    }) {
                                        Image(systemName: copiedField == .twoFA ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 20))
                                            .foregroundColor(copiedField == .twoFA ? .green : .primary)
                                            .frame(width: 44, height: 44)
                                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                            .cornerRadius(10)
                                    }
                                    
                                    ZStack {
                                        Circle()
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 3)
                                            .frame(width: 28, height: 28)
                                        
                                        let progress = Double(totp.remainingSeconds) / Double(account.totpPeriod)
                                        Circle()
                                            .trim(from: 0, to: CGFloat(progress))
                                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                            .frame(width: 28, height: 28)
                                            .rotationEffect(.degrees(-90))
                                            .animation(.linear(duration: 1.0), value: progress)
                                        
                                        Text("\(totp.remainingSeconds)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.primary)
                                    }
                                } else {
                                    Text("لا يوجد رمز تحقق صالح")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                            .environment(\.layoutDirection, .leftToRight)
                            
                            if currentTOTP != nil {
                                Divider()
                                VStack(spacing: 8) {
                                    if let secret = account.totpSecret, !secret.isEmpty {
                                        HStack(spacing: 12) {
                                            Text("المفتاح السري")
                                                .font(.caption)
                                                .foregroundColor(.secondary)

                                            Spacer()

                                            Text(isTOTPSecretVisible ? secret : String(repeating: "•", count: min(max(secret.count, 8), 24)))
                                                .font(.caption.monospaced())
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.65)
                                                .privacySensitive()

                                            Button {
                                                isTOTPSecretVisible.toggle()
                                            } label: {
                                                Image(systemName: isTOTPSecretVisible ? "eye.slash" : "eye")
                                                    .foregroundColor(.secondary)
                                            }
                                            .accessibilityLabel(isTOTPSecretVisible ? "إخفاء المفتاح السري" : "إظهار المفتاح السري")
                                        }
                                    }
                                    HStack {
                                        Text("الخوارزمية")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(account.totpAlgorithm.rawValue.uppercased())
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                    }
                                    HStack {
                                        Text("عدد الخانات")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(account.totpDigits)")
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                    }
                                    HStack {
                                        Text("الفترة")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(account.totpPeriod) ثانية")
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                    }
                                    
                                    Text("تأكد من ضبط وقت الجهاز تلقائيًا إذا كانت الرموز غير متطابقة.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.trailing)
                                        .padding(.top, 4)
                                }
                                .environment(\.layoutDirection, .rightToLeft)
                            }
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                }
                
                // Backup Codes Section
                if account.hasBackupFile {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("أكواد احتياطية (.txt)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            Text("تم حفظ أكواد احتياطية")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Button(action: {
                                // visual only
                            }) {
                                Label("عرض", systemImage: "doc.text.magnifyingglass")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                    .cornerRadius(10)
                            }
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                }
                
                // Notes Section
                if !account.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ملاحظات")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(alignment: .top) {
                            Text(account.notes)
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Button(action: {
                                copyToClipboard(account.notes, field: .notes)
                            }) {
                                Image(systemName: copiedField == .notes ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 20))
                                    .foregroundColor(copiedField == .notes ? .green : .primary)
                                    .frame(width: 44, height: 44)
                                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                    .cornerRadius(10)
                            }
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                }
            }
            .padding()
            .environment(\.layoutDirection, .rightToLeft) // Main content Arabic layout
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("تفاصيل الحساب: \(account.serviceName)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active {
                isPasswordVisible = false
                isTOTPSecretVisible = false
                isTOTPCodeRevealed = false
            }
        }
        .onChange(of: settings.hideTOTPCodesByDefault) { shouldHide in
            if shouldHide {
                isTOTPCodeRevealed = false
            }
        }
    }
    
    // Helper to build consistent detail rows
    private func detailRow(label: String, value: String, field: CopiedField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Text(value)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Button(action: {
                    copyToClipboard(value, field: field)
                }) {
                    Image(systemName: copiedField == field ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 20))
                        .foregroundColor(copiedField == field ? .green : .primary)
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .cornerRadius(10)
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(10)
        }
    }
    
    // Special field for password with toggles
    private func passwordRow() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("الباسورد")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                if isPasswordVisible {
                    Text(account.password)
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(String(repeating: "•", count: account.password.count > 0 ? 8 : 0))
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Button(action: {
                    isPasswordVisible.toggle()
                }) {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .cornerRadius(10)
                }
                
                Button(action: {
                    copyToClipboard(account.password, field: .password)
                }) {
                    Image(systemName: copiedField == .password ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 20))
                        .foregroundColor(copiedField == .password ? .green : .primary)
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .cornerRadius(10)
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(10)
        }
    }
    
    private var shouldMaskTOTPCode: Bool {
        settings.hideTOTPCodesByDefault && !isTOTPCodeRevealed
    }

    private func displayedTOTPCode(_ code: String) -> String {
        guard !shouldMaskTOTPCode else { return "••• •••" }
        let midpoint = code.index(code.startIndex, offsetBy: code.count / 2)
        return "\(code[..<midpoint]) \(code[midpoint...])"
    }

    private func copyToClipboard(_ text: String, field: CopiedField) {
        guard !text.isEmpty else { return }
        SecureClipboardService.copy(text, expiresAfter: settings.clipboardClearDelay.seconds)
        copiedField = field
        
        // Reset feedback after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedField == field {
                copiedField = nil
            }
        }
    }
}

#if DEBUG
#Preview("With 2FA and Backup") {
    NavigationStack {
        AccountDetailView(account: VaultAccount(siteURL: "google.com", email: "user@gmail.com", password: "secretpassword", username: "user123", notes: "Some notes", has2FA: true, hasBackupFile: true))
            .environmentObject(VaultSecuritySettings())
            .environment(\.layoutDirection, .rightToLeft)
            .preferredColorScheme(.dark)
    }
}

#Preview("Without 2FA") {
    NavigationStack {
        AccountDetailView(account: VaultAccount(siteURL: "microsoft.com", email: "work@domain.com", password: "password123", username: "", notes: "", has2FA: false, hasBackupFile: false))
            .environmentObject(VaultSecuritySettings())
            .environment(\.layoutDirection, .rightToLeft)
            .preferredColorScheme(.dark)
    }
}
#endif
