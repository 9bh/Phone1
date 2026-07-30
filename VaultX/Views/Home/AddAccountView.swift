import SwiftUI

@MainActor
final class AccountEditorSession: ObservableObject {
  @Published var isPresented = false
  @Published private(set) var editingAccountID: UUID?

  @Published var siteURL = ""
  @Published var email = ""
  @Published var password = ""
  @Published var username = ""
  @Published var notes = ""
  @Published var has2FA = false
  @Published var hasBackupFile = false

  @Published var totpSecret = ""
  @Published var totpIssuer = ""
  @Published var totpAlgorithm: TOTPAlgorithm = .sha1
  @Published var totpDigits = 6
  @Published var totpPeriod = 30

  var isEditing: Bool {
    editingAccountID != nil
  }

  func beginNewAccount() {
    resetDraft()
    isPresented = true
  }

  func beginEditing(_ account: VaultAccount) {
    editingAccountID = account.id
    siteURL = account.siteURL
    email = account.email
    password = account.password
    username = account.username
    notes = account.notes
    has2FA = account.has2FA
    hasBackupFile = account.hasBackupFile
    totpSecret = account.totpSecret ?? ""
    totpIssuer = account.totpIssuer ?? ""
    totpAlgorithm = account.totpAlgorithm
    totpDigits = account.totpDigits
    totpPeriod = account.totpPeriod
    isPresented = true
  }

  func cancel() {
    isPresented = false
    resetDraft()
  }

  func complete() {
    isPresented = false
    resetDraft()
  }

  private func resetDraft() {
    editingAccountID = nil
    siteURL = ""
    email = ""
    password = ""
    username = ""
    notes = ""
    has2FA = false
    hasBackupFile = false
    totpSecret = ""
    totpIssuer = ""
    totpAlgorithm = .sha1
    totpDigits = 6
    totpPeriod = 30
  }

  #if DEBUG
    static func preview(account: VaultAccount? = nil) -> AccountEditorSession {
      let session = AccountEditorSession()
      if let account {
        session.beginEditing(account)
      } else {
        session.beginNewAccount()
      }
      return session
    }
  #endif
}

private enum AccountEditorFocusField: Hashable {
  case siteURL
  case email
  case password
  case username
  case totpSecret
  case totpIssuer
}

private enum AccountEditorScrollAnchor: Hashable {
  case identity
  case totpSecret
}

struct AddAccountView: View {
  @EnvironmentObject private var store: VaultAccountsStore
  @EnvironmentObject private var editorSession: AccountEditorSession

  @State private var isPasswordVisible = false
  @State private var isTotpSecretVisible = false
  @State private var identityError: String?
  @State private var totpError: String?
  @FocusState private var focusedField: AccountEditorFocusField?

  var body: some View {
    ZStack {
      Color(uiColor: .systemGroupedBackground)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        ScrollViewReader { proxy in
          topBar(proxy: proxy)

          ScrollView {
            VStack(spacing: 24) {
              identitySection
                .id(AccountEditorScrollAnchor.identity)

              twoFactorSection

              backupCodesSection
              notesSection
            }
            .padding()
            .environment(\.layoutDirection, .rightToLeft)
          }
          .scrollDismissesKeyboard(.interactively)
        }
      }
    }
    .interactiveDismissDisabled(true)
    .alert(item: $store.storageAlert) { alert in
      Alert(
        title: Text(alert.title),
        message: Text(alert.message),
        dismissButton: .default(Text("حسناً"))
      )
    }
    .onChange(of: editorSession.siteURL) { _ in clearIdentityErrorWhenPossible() }
    .onChange(of: editorSession.email) { _ in clearIdentityErrorWhenPossible() }
    .onChange(of: editorSession.username) { _ in clearIdentityErrorWhenPossible() }
    .onChange(of: editorSession.totpSecret) { _ in
      if totpError != nil {
        totpError = nil
      }
    }
  }

  private func topBar(proxy: ScrollViewProxy) -> some View {
    HStack {
      Button {
        editorSession.cancel()
      } label: {
        Text("إلغاء")
          .font(.body)
          .foregroundColor(.accentColor)
      }

      Spacer()

      Text(editorSession.isEditing ? "تعديل الحساب" : "إضافة حساب")
        .font(.headline)
        .foregroundColor(.primary)

      Spacer()

      Button {
        validateAndSave(using: proxy)
      } label: {
        if store.isMutationInProgress {
          ProgressView()
        } else {
          Text("حفظ")
            .font(.body.weight(.semibold))
            .foregroundColor(.accentColor)
        }
      }
      .disabled(store.isMutationInProgress)
    }
    .padding()
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .environment(\.layoutDirection, .leftToRight)
  }

  private var identitySection: some View {
    VStack(spacing: 16) {
      if let identityError {
        Text(identityError)
          .font(.caption)
          .foregroundColor(.red)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .multilineTextAlignment(.trailing)
      }

      inputField(
        label: "رابط الموقع:",
        placeholder: "https://www.website.com",
        text: $editorSession.siteURL,
        keyboardType: .URL,
        focus: .siteURL
      )

      inputField(
        label: "الإيميل:",
        placeholder: "email@email.com",
        text: $editorSession.email,
        keyboardType: .emailAddress,
        focus: .email
      )

      passwordField()

      inputField(
        label: "اسم المستخدم:",
        placeholder: "username",
        text: $editorSession.username,
        focus: .username
      )
    }
  }

  private var twoFactorSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("التحقق بخطوتين (2FA):")
        .font(.subheadline)
        .foregroundColor(.secondary)

      if !editorSession.has2FA {
        Button {
          editorSession.has2FA = true
        } label: {
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
              editorSession.has2FA = false
              editorSession.totpSecret = ""
              editorSession.totpIssuer = ""
              totpError = nil
              if focusedField == .totpSecret || focusedField == .totpIssuer {
                focusedField = nil
              }
            } label: {
              Image(systemName: "trash")
                .foregroundColor(.red)
            }
          }

          VStack(alignment: .leading, spacing: 6) {
            Text("المفتاح السري (Base32):")
              .font(.subheadline)
              .foregroundColor(.secondary)

            HStack {
              if isTotpSecretVisible {
                TextField("Secret Key", text: $editorSession.totpSecret)
                  .autocapitalization(.none)
                  .disableAutocorrection(true)
                  .focused($focusedField, equals: .totpSecret)
              } else {
                SecureField("Secret Key", text: $editorSession.totpSecret)
                  .focused($focusedField, equals: .totpSecret)
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

            if let totpError {
              Text(totpError)
                .font(.caption)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
            }
          }
          .id(AccountEditorScrollAnchor.totpSecret)

          inputField(
            label: "الجهة المصدرة (اختياري):",
            placeholder: "Issuer",
            text: $editorSession.totpIssuer,
            focus: .totpIssuer
          )

          HStack {
            Text("الخوارزمية:")
              .font(.subheadline)
              .foregroundColor(.secondary)
            Spacer()
            Picker("الخوارزمية", selection: $editorSession.totpAlgorithm) {
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
            Picker("الخانات", selection: $editorSession.totpDigits) {
              Text("6").tag(6)
              Text("8").tag(8)
            }
          }

          HStack {
            Text("الفترة:")
              .font(.subheadline)
              .foregroundColor(.secondary)
            Spacer()
            Picker("الفترة", selection: $editorSession.totpPeriod) {
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
  }

  private var backupCodesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("أكواد احتياطية (.txt):")
        .font(.subheadline)
        .foregroundColor(.secondary)

      HStack(spacing: 12) {
        Button {
          editorSession.hasBackupFile = true
        } label: {
          Label("تحميل ملف", systemImage: "arrow.up.doc")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(10)
        }

        if editorSession.hasBackupFile {
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
  }

  private var notesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("ملاحظات:")
        .font(.subheadline)
        .foregroundColor(.secondary)

      TextEditor(text: $editorSession.notes)
        .frame(minHeight: 120)
        .padding(8)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
  }

  private func validateAndSave(using proxy: ScrollViewProxy) {
    guard !store.isMutationInProgress else { return }

    focusedField = nil
    identityError = nil
    totpError = nil

    let hasIdentity =
      !editorSession.siteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !editorSession.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !editorSession.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    guard hasIdentity else {
      identityError = "أدخل رابط الموقع أو الإيميل أو اسم المستخدم على الأقل."
      scrollToError(.identity, focus: .siteURL, using: proxy)
      return
    }

    if editorSession.has2FA {
      let trimmedSecret = editorSession.totpSecret.trimmingCharacters(in: .whitespacesAndNewlines)

      guard !trimmedSecret.isEmpty else {
        totpError = "يجب إدخال المفتاح السري."
        scrollToError(.totpSecret, focus: .totpSecret, using: proxy)
        return
      }

      do {
        _ = try Base32Decoder.decode(trimmedSecret)
        editorSession.totpSecret = trimmedSecret
      } catch {
        totpError = "المفتاح السري غير صالح. أدخل مفتاح Base32 صحيحًا."
        scrollToError(.totpSecret, focus: .totpSecret, using: proxy)
        return
      }
    }

    Task {
      let account = VaultAccount(
        id: editorSession.editingAccountID ?? UUID(),
        siteURL: editorSession.siteURL,
        email: editorSession.email,
        password: editorSession.password,
        username: editorSession.username,
        notes: editorSession.notes,
        has2FA: editorSession.has2FA,
        hasBackupFile: editorSession.hasBackupFile,
        totpSecret: editorSession.has2FA ? editorSession.totpSecret : nil,
        totpIssuer: editorSession.has2FA ? editorSession.totpIssuer : nil,
        totpAlgorithm: editorSession.totpAlgorithm,
        totpDigits: editorSession.totpDigits,
        totpPeriod: editorSession.totpPeriod
      )

      let result: Result<Void, VaultMutationError>
      if editorSession.isEditing {
        result = await store.updateAccount(account)
      } else {
        result = await store.addAccount(account)
      }

      if case .success = result {
        editorSession.complete()
      }
    }
  }

  private func scrollToError(
    _ anchor: AccountEditorScrollAnchor,
    focus: AccountEditorFocusField,
    using proxy: ScrollViewProxy
  ) {
    DispatchQueue.main.async {
      withAnimation(.easeInOut(duration: 0.3)) {
        proxy.scrollTo(anchor, anchor: .center)
      }
      focusedField = focus
    }
  }

  private func clearIdentityErrorWhenPossible() {
    guard identityError != nil else { return }

    if !editorSession.siteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !editorSession.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !editorSession.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      identityError = nil
    }
  }

  private func inputField(
    label: String,
    placeholder: String,
    text: Binding<String>,
    keyboardType: UIKeyboardType = .default,
    focus: AccountEditorFocusField
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.subheadline)
        .foregroundColor(.secondary)

      TextField(placeholder, text: text)
        .keyboardType(keyboardType)
        .autocapitalization(.none)
        .focused($focusedField, equals: focus)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
  }

  private func passwordField() -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("الباسورد:")
        .font(.subheadline)
        .foregroundColor(.secondary)

      HStack(spacing: 12) {
        if isPasswordVisible {
          TextField("password", text: $editorSession.password)
            .autocapitalization(.none)
            .focused($focusedField, equals: .password)
        } else {
          SecureField("password", text: $editorSession.password)
            .autocapitalization(.none)
            .focused($focusedField, equals: .password)
        }

        Button {
          isPasswordVisible.toggle()
        } label: {
          Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
            .foregroundColor(.secondary)
        }

        Button(action: {}) {
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
      .environmentObject(AccountEditorSession.preview())
      .preferredColorScheme(.dark)
  }

  #Preview("Edit Account") {
    AddAccountView()
      .environmentObject(VaultAccountsStore.preview())
      .environmentObject(
        AccountEditorSession.preview(
          account: VaultAccount(
            siteURL: "google.com",
            email: "user@gmail.com",
            password: "password123",
            username: "user123",
            notes: "Some notes",
            has2FA: true,
            hasBackupFile: false
          ))
      )
      .preferredColorScheme(.dark)
  }
#endif
