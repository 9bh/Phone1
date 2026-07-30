import SwiftUI

struct AccountCardView: View {
    let account: VaultAccount
    @ObservedObject private var clock = TOTPClock.shared
    @State private var copiedFeedback = false
    
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
            // Top Row
            HStack(spacing: 16) {
                // Service Icon on the left
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
                
                // Circular Timer on the far right
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
            
            // Bottom Row
            if account.has2FA {
                HStack {
                    if let totp = currentTOTP {
                        Button {
                            copyCode(totp.value)
                        } label: {
                            HStack(spacing: 12) {
                                let codeString = totp.value
                                let midIndex = codeString.index(codeString.startIndex, offsetBy: codeString.count / 2)
                                let firstHalf = String(codeString[..<midIndex])
                                let secondHalf = String(codeString[midIndex...])
                                
                                Text("\(firstHalf) \(secondHalf)")
                                    .font(.system(size: 34, weight: .regular, design: .rounded))
                                    .foregroundColor(.accentColor)
                                    .privacySensitive()
                                
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
                            }
                        }
                        .buttonStyle(.plain)
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
        .environment(\.layoutDirection, .leftToRight) // Force physical layout
    }
    
    private func copyCode(_ code: String) {
        UIPasteboard.general.string = code
        withAnimation { copiedFeedback = true }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copiedFeedback = false }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            if UIPasteboard.general.string == code {
                UIPasteboard.general.string = ""
            }
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color(uiColor: .systemBackground).ignoresSafeArea()
        AccountCardView(account: VaultAccount(siteURL: "google.com", email: "test@google.com", password: "", username: "", notes: ""))
            .padding()
    }
    .preferredColorScheme(.dark)
}
#endif
