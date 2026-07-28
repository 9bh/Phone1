import SwiftUI

struct AccountCardView: View {
    let account: VaultAccount
    
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
                    
                    Text(!account.email.isEmpty ? account.email : account.username)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 16)
                
                // Circular Timer on the far right
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 3)
                        .frame(width: 28, height: 28)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(-90))
                }
            }
            
            // Bottom Row
            HStack {
                let codeString = account.displayCode.replacingOccurrences(of: " ", with: "")
                Text(codeString.map { String($0) }.joined(separator: " "))
                    .font(.system(size: 34, weight: .regular, design: .rounded))
                    .foregroundColor(.accentColor)
                Spacer()
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(20)
        .environment(\.layoutDirection, .leftToRight) // Force physical layout
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
