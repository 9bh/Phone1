import SwiftUI

struct AccountCardView: View {
    let account: VaultAccount
    @EnvironmentObject private var settings: VaultSecuritySettings
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var clock = TOTPClock.shared
    @State private var copiedFeedback = false
    @State private var isTOTPRevealed = false

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
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        .frame(width: 48, height: 48)

                    Image(systemName: account.iconName)
                        .font(.system(size: 24))
                        .foregroundColor(.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.serviceName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if !account.username.isEmpty {
                        let formattedUsername = account.username.hasPrefix("@") ? account.username : "@\(account.username)"
                        Text(formattedUsername)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if !account.email.isEmpty {
                        Text(account.email)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 16)

                if account.has2FA, let totp = currentTOTP {
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
                }
            }

            if account.has2FA {
                HStack(spacing: 10) {
                    if let totp = currentTOTP {
                        Button {
                            copyCode(totp.value)
                        } label: {
                            Text(displayedCode(totp.value))
                                .font(.system(size: 34, weight: .regular, design: .rounded))
                                .foregroundColor(.accentColor)
                                .privacySensitive()
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.18), value: shouldMaskTOTP)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(shouldMaskTOTP ? "رمز التحقق مخفي، اضغط للنسخ" : "نسخ رمز التحقق")

                        if settings.hideTOTPCodesByDefault {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    isTOTPRevealed.toggle()
                                }
                            } label: {
                                Image(systemName: isTOTPRevealed ? "eye.slash" : "eye")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 34, height: 34)
                                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isTOTPRevealed ? "إخفاء رمز التحقق" : "إظهار رمز التحقق")
                        }

                        if copiedFeedback {
                            Text("تم نسخ الرمز")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.2))
                                .foregroundColor(.accentColor)
                                .cornerRadius(6)
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                    } else {
                        Text("لا يوجد رمز تحقق صالح")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                    Spacer()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(20)
        .environment(\.layoutDirection, .leftToRight)
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active {
                isTOTPRevealed = false
            }
        }
        .onChange(of: settings.hideTOTPCodesByDefault) { shouldHide in
            if shouldHide {
                isTOTPRevealed = false
            }
        }
    }

    private var shouldMaskTOTP: Bool {
        settings.hideTOTPCodesByDefault && !isTOTPRevealed
    }

    private func displayedCode(_ code: String) -> String {
        guard !shouldMaskTOTP else { return "••• •••" }
        let midpoint = code.index(code.startIndex, offsetBy: code.count / 2)
        return "\(code[..<midpoint]) \(code[midpoint...])"
    }

    private func copyCode(_ code: String) {
        SecureClipboardService.copy(code, expiresAfter: settings.clipboardClearDelay.seconds)
        withAnimation { copiedFeedback = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copiedFeedback = false }
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color(uiColor: .systemBackground).ignoresSafeArea()
        AccountCardView(account: VaultAccount(siteURL: "google.com", email: "test@google.com", password: "", username: "", notes: ""))
            .environmentObject(VaultSecuritySettings())
            .padding()
    }
    .preferredColorScheme(.dark)
}
#endif
