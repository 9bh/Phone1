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
    @State private var has2FA = false
    @State private var hasBackupFile = false
    
    @State private var totpSecret = ""
    @State private var isTotpSecretVisible = false
    @State private var totpIssuer = ""
    @State private var totpAlgorithm: TOTPAlgorithm = .sha1
    @State private var totpDigits: Int = 6
    @State private var totpPeriod: Int = 30
    @State private var totpError: String? = nil
    
    var accountToEdit: VaultAccount?
    
    init(accountToEdit: VaultAccount? = nil) {
        self.accountToEdit = accountToEdit
        _siteURL = State(initialValue: accountToEdit?.siteURL ?? "")
        _email = State(initialValue: accountToEdit?.email ?? "")
        _password = State(initialValue: accountToEdit?.password ?? "")
        _username = State(initialValue: accountToEdit?.username ?? "")
        _notes = State(initialValue: accountToEdit?.notes ?? "")
        _has2FA = State(initialValue: accountToEdit?.has2FA ?? false)
        _hasBackupFile = State(initialValue: accountToEdit?.hasBackupFile ?? false)
        _totpSecret = State(initialValue: accountToEdit?.totpSecret ?? "")
        _totpIssuer = State(initialValue: accountToEdit?.totpIssuer ?? "")
        _totpAlgorithm = State(initialValue: accountToEdit?.totpAlgorithm ?? .sha1)
        _totpDigits = State(initialValue: accountToEdit?.totpDigits ?? 6)
        _totpPeriod = State(initialValue: accountToEdit?.totpPeriod ?? 30)
    }
    
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
                    
                    Text(accountToEdit == nil ? "إضافة حساب" : "تعديل الحساب")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        guard !store.isMutationInProgress else { return }
                        
                        if has2FA {
                            guard !totpSecret.isEmpty else {
                                totpError = "يجب إدخال المفتاح السري"
                                return
                            }
                            do {
                                _ = try Base32Decoder.decode(totpSecret)
                                totpError = nil
                            } catch {
                                totpError = "المفتاح السري غير صالح (يجب أن يكون Base32)"
                                return
                            }
                        }
                        
                        Task {
                            if let existing = accountToEdit {
                                let updatedAccount = VaultAccount(
                                    id: existing.id,
                                    siteURL: siteURL,
                                    email: email,
                                    password: password,
                                    username: username,
                                    notes: notes,
                                    has2FA: has2FA,
                                    hasBackupFile: hasBackupFile,
                                    totpSecret: has2FA ? totpSecret : nil,
                                    totpIssuer: has2FA ? totpIssuer : nil,
                                    totpAlgorithm: totpAlgorithm,
                                    totpDigits: totpDigits,
                                    totpPeriod: totpPeriod
                                )
                                let result = await store.updateAccount(updatedAccount)
                                if case .success = result {
                                    dismiss()
                                }
                            } else {
                                let newAccount = VaultAccount(
                                    siteURL: siteURL,
                                    email: email,
                                    password: password,
                                    username: username,
                                    notes: notes,
                                    has2FA: has2FA,
                                    hasBackupFile: hasBackupFile,
                                    totpSecret: has2FA ? totpSecret : nil,
                                    totpIssuer: has2FA ? totpIssuer : nil,
                                    totpAlgorithm: totpAlgorithm,
                                    totpDigits: totpDigits,
                                    totpPeriod: totpPeriod
                                )
                                let result = await store.addAccount(newAccount)
                                if case .success = result {
                                    dismiss()
                                }
                            }
                        }
                    }) {
                        if store.isMutationInProgress {
                            ProgressView()
                        } else {
                            Text("حفظ")
                                .font(.body.weight(.semibold))
                                .foregroundColor((siteURL.isEmpty && email.isEmpty && username.isEmpty) ? .secondary : .accentColor)
                        }
                    }
                    .disabled(store.isMutationInProgress || (siteURL.isEmpty && email.isEmpty && username.isEmpty))
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .environment(\.layoutDirection, .leftToRight)
                .alert(item: $store.storageAlert) { alert in
                    Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("حسناً")))
                }
                
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
                            Text("التحقق بخطوتين (2FA):")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if !has2FA {
                                Button(action: {
                                    has2FA = true
                                }) {
                                    Label("إضافة 2FA", systemImage: "plus.circle")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                                        .cornerRadius(10)
                                }
                                .foregroundColor(.accentColor)
                            } else {
                                VStack(spacing: 16) {
                                    HStack {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundColor(.green)
                                        Text("تم تفعيل 2FA")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Button {
                                            has2FA = false
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                    }
                                    
                                    if let error = totpError {
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("المفتاح السري (Base32):")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        HStack {
                                            if isTotpSecretVisible {
                                                TextField("Secret Key", text: $totpSecret)
                                                    .autocapitalization(.none)
                                                    .disableAutocorrection(true)
                                            } else {
                                                SecureField("Secret Key", text: $totpSecret)
                                            }
                                            
                                            Button {
                                                isTotpSecretVisible.toggle()
                                            } label: {
                                                Image(systemName: isTotpSecretVisible ? "eye.slash" : "eye")
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(12)
                                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                        .cornerRadius(10)
                                    }
                                    
                                    inputField(label: "الجهة المصدرة (اختياري):", placeholder: "Issuer", text: $totpIssuer)
                                    
                                    HStack {
                                        Text("الخوارزمية:")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Picker("الخوارزمية", selection: $totpAlgorithm) {
                                            Text("SHA1").tag(TOTPAlgorithm.sha1)
                                            Text("SHA256").tag(TOTPAlgorithm.sha256)
                                            Text("SHA512").tag(TOTPAlgorithm.sha512)
                                        }
                                    }
                                    
                                    HStack {
                                        Text("الخانات:")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Picker("الخانات", selection: $totpDigits) {
                                            Text("6").tag(6)
                                            Text("8").tag(8)
                                        }
                                    }
                                    
                                    HStack {
                                        Text("الفترة:")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Picker("الفترة", selection: $totpPeriod) {
                                            Text("30").tag(30)
                                            Text("60").tag(60)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .cornerRadius(12)
                            }
                        }
                        
                        // Backup Codes Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("أكواد احتياطية (.txt):")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    hasBackupFile = true
                                }) {
                                    Label("تحميل ملف", systemImage: "arrow.up.doc")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                                        .cornerRadius(10)
                                }
                                
                                if hasBackupFile {
                                    Button(action: {}) {
                                        Label("عرض", systemImage: "doc.text.magnifyingglass")
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                                            .cornerRadius(10)
                                    }
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
#Preview("New Account") {
    AddAccountView()
        .environmentObject(VaultAccountsStore.preview())
        .preferredColorScheme(.dark)
}

#Preview("Edit Account") {
    AddAccountView(accountToEdit: VaultAccount(siteURL: "google.com", email: "user@gmail.com", password: "password123", username: "user123", notes: "Some notes", has2FA: true, hasBackupFile: false))
        .environmentObject(VaultAccountsStore.preview())
        .preferredColorScheme(.dark)
}
#endif
