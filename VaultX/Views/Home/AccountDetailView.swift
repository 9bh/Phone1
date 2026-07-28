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
    
    @State private var isPasswordVisible = false
    @State private var copiedField: CopiedField? = nil
    
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
                                
                                let codeString = account.displayCode.replacingOccurrences(of: " ", with: "")
                                Text(codeString.map { String($0) }.joined(separator: " "))
                                    .font(.system(size: 32, weight: .regular, design: .monospaced))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button(action: {
                                    copyToClipboard(account.displayCode, field: .twoFA)
                                }) {
                                    Image(systemName: copiedField == .twoFA ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 20))
                                        .foregroundColor(copiedField == .twoFA ? .green : .primary)
                                        .frame(width: 44, height: 44)
                                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                        .cornerRadius(10)
                                }
                                
                                // Circular Timer Placeholder
                                ZStack {
                                    Circle()
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 3)
                                        .frame(width: 24, height: 24)
                                    
                                    Circle()
                                        .trim(from: 0, to: 0.7)
                                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                        .frame(width: 24, height: 24)
                                        .rotationEffect(.degrees(-90))
                                }
                            }
                            .environment(\.layoutDirection, .leftToRight)
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
    
    private func copyToClipboard(_ text: String, field: CopiedField) {
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
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
            .environment(\.layoutDirection, .rightToLeft)
            .preferredColorScheme(.dark)
    }
}

#Preview("Without 2FA") {
    NavigationStack {
        AccountDetailView(account: VaultAccount(siteURL: "microsoft.com", email: "work@domain.com", password: "password123", username: "", notes: "", has2FA: false, hasBackupFile: false))
            .environment(\.layoutDirection, .rightToLeft)
            .preferredColorScheme(.dark)
    }
}
#endif
