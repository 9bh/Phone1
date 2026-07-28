import SwiftUI

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: VaultAccountsStore
    
    @State private var siteURL = ""
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var notes = ""
    @State private var isPasswordVisible = false
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom Top Bar (Forced LTR physical layout)
                HStack {
                    Button(action: { dismiss() }) {
                        Text("إلغاء")
                            .font(.body)
                            .foregroundColor(.accentColor)
                    }
                    
                    Spacer()
                    
                    Text("إضافة حساب")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        let newAccount = VaultAccount(
                            siteURL: siteURL,
                            email: email,
                            password: password,
                            username: username,
                            notes: notes
                        )
                        store.addAccount(newAccount)
                        dismiss()
                    }) {
                        Text("حفظ")
                            .font(.body.weight(.semibold))
                            .foregroundColor((siteURL.isEmpty && email.isEmpty && username.isEmpty) ? .secondary : .accentColor)
                    }
                    .disabled(siteURL.isEmpty && email.isEmpty && username.isEmpty)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .environment(\.layoutDirection, .leftToRight)
                
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // Input Fields Group
                        VStack(spacing: 16) {
                            inputField(label: "رابط الموقع:", placeholder: "https://www.website.com", text: $siteURL, keyboardType: .URL)
                            inputField(label: "الإيميل:", placeholder: "email@email.com", text: $email, keyboardType: .emailAddress)
                            passwordField()
                            inputField(label: "اسم المستخدم:", placeholder: "username", text: $username)
                        }
                        
                        // 2FA Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("مولد 2FA:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            VStack(spacing: 16) {
                                HStack {
                                    Image(systemName: "shield.checkerboard")
                                        .foregroundColor(.accentColor)
                                        .font(.system(size: 28))
                                    
                                    Spacer()
                                    
                                    Text("123 456")
                                        .font(.system(size: 32, weight: .regular, design: .monospaced))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
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
                                
                                Button(action: {
                                    // visual only
                                }) {
                                    Text("نسخ الرمز")
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.accentColor)
                                        .cornerRadius(10)
                                }
                            }
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }
                        
                        // Backup Codes Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("أكواد احتياطية (.txt):")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 12) {
                                Button(action: {}) {
                                    Label("تحميل ملف", systemImage: "arrow.up.doc")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                                        .cornerRadius(10)
                                }
                                
                                Button(action: {}) {
                                    Label("عرض", systemImage: "doc.text.magnifyingglass")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                                        .cornerRadius(10)
                                }
                            }
                            .foregroundColor(.accentColor)
                        }
                        
                        // Notes Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ملاحظات:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: $notes)
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .cornerRadius(12)
                        }
                        
                    }
                    .padding()
                    .environment(\.layoutDirection, .rightToLeft) // Main content Arabic layout
                }
            }
        }
    }
    
    // Helper to build consistent input fields
    private func inputField(label: String, placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .autocapitalization(.none)
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(10)
        }
    }
    
    // Special field for password with toggles
    private func passwordField() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("الباسورد:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                if isPasswordVisible {
                    TextField("password", text: $password)
                        .autocapitalization(.none)
                } else {
                    SecureField("password", text: $password)
                        .autocapitalization(.none)
                }
                
                Button(action: {
                    isPasswordVisible.toggle()
                }) {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                
                Button(action: {
                    // visual copy placeholder
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(10)
        }
    }
}

#if DEBUG
#Preview {
    AddAccountView()
        .environmentObject(VaultAccountsStore())
        .preferredColorScheme(.dark)
}
#endif
