import SwiftUI
import UniformTypeIdentifiers

private struct VaultBackupAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum BackupSensitiveAction {
    case createBackup
    case replaceAll
}

struct VaultBackupRestoreView: View {
    @EnvironmentObject private var store: VaultAccountsStore
    @EnvironmentObject private var appState: AppLockState
    @EnvironmentObject private var session: VaultBackupRestoreSession

    @State private var pendingSensitiveAction: BackupSensitiveAction?
    @State private var isShowingOwnerVerification = false
    @State private var isShowingCreatePassword = false
    @State private var isShowingDecryptPassword = false
    @State private var isShowingReplaceConfirmation = false
    @State private var isShowingFileImporter = false
    @State private var isShowingFileExporter = false
    @State private var isFileImporterPresentationActive = false
    @State private var isFileExporterPresentationActive = false
    @State private var exportDocument: VaultBackupDocument?
    @State private var exportFilename = "VaultX_Backup"
    @State private var alert: VaultBackupAlert?

    private let cryptoService = VaultBackupCryptoService()

    var body: some View {
        List {
            Section {
                Label {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("نسخة احتياطية مشفرة")
                            .font(.headline)
                        Text("تتضمن الحسابات وكلمات المرور ومفاتيح التحقق بخطوتين.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } icon: {
                    Image(systemName: "lock.doc.fill")
                        .foregroundColor(.accentColor)
                }

                Button {
                    requestOwnerVerification(for: .createBackup)
                } label: {
                    Label("إنشاء نسخة احتياطية مشفرة", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .disabled(store.accounts.isEmpty || store.isMutationInProgress || session.isBusy)
            } header: {
                Text("إنشاء نسخة")
            } footer: {
                Text("ستنشئ كلمة مرور مستقلة للملف. لا يحفظ VaultX هذه الكلمة ولا يمكن استعادتها عند نسيانها.")
            }

            Section {
                Button {
                    chooseBackupFile()
                } label: {
                    Label("اختيار ملف VaultX", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .disabled(store.isMutationInProgress || session.isBusy)

                if !session.sourceFilename.isEmpty {
                    LabeledContent("الملف المحدد") {
                        Text(session.sourceFilename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }


                if session.encryptedFileData != nil, session.payload == nil {
                    Button {
                        isShowingDecryptPassword = true
                    } label: {
                        Label("إدخال كلمة مرور الملف", systemImage: "key.fill")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            } header: {
                Text("استعادة نسخة")
            } footer: {
                Text("تُقرأ النسخة وتُفك محليًا على الجهاز بعد إدخال كلمة مرورها.")
            }

            if let summary = session.summary, session.payload != nil {
                Section("ملخص النسخة") {
                    summaryRow("إجمالي الحسابات", value: summary.totalAccounts)
                    summaryRow("تحتوي على كلمات مرور", value: summary.passwordAccounts)
                    summaryRow("تحتوي على 2FA", value: summary.twoFactorAccounts)
                    summaryRow("حسابات جديدة", value: summary.newAccounts)
                    summaryRow("موجودة مسبقًا", value: summary.identicalAccounts)
                    summaryRow("تعارضات", value: summary.conflicts + summary.ambiguousAccounts)

                    NavigationLink {
                        VaultBackupReviewView()
                            .environmentObject(session)
                    } label: {
                        Label("مراجعة ودمج الحسابات", systemImage: "checklist")
                    }

                    Button(role: .destructive) {
                        requestOwnerVerification(for: .replaceAll)
                    } label: {
                        Label("استبدال جميع الحسابات", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .disabled(summary.totalAccounts == 0)
                }
            }

            Section("الحماية") {
                securityRow("التشفير", value: "AES-256-GCM")
                securityRow("اشتقاق المفتاح", value: "PBKDF2-SHA256")
                securityRow("المعالجة", value: "داخل الجهاز")
                securityRow("كلمة مرور النسخة", value: "لا تُحفظ")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .navigationTitle("النسخ الاحتياطي والاستعادة")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if session.isBusy {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView("جاري تنفيذ العملية الآمنة...")
                        .padding(22)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .environment(\.layoutDirection, .rightToLeft)
            }
        }
        .sheet(isPresented: $isShowingOwnerVerification) {
            OwnerVerificationView(
                title: ownerVerificationTitle,
                reason: ownerVerificationReason,
                onVerified: ownerVerificationSucceeded
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $isShowingCreatePassword) {
            BackupPasswordCreationView { password in
                createEncryptedBackup(password: password)
            }
        }
        .sheet(isPresented: $isShowingDecryptPassword) {
            BackupPasswordEntryView(
                filename: session.sourceFilename,
                onUnlock: decryptSelectedBackup
            )
        }
        .sheet(isPresented: $isShowingReplaceConfirmation) {
            ReplaceVaultConfirmationView(
                accountCount: session.payload?.accounts.count ?? 0,
                onConfirm: replaceAllAccounts
            )
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.vaultXBackup],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .fileExporter(
            isPresented: $isShowingFileExporter,
            document: exportDocument,
            contentType: .vaultXBackup,
            defaultFilename: exportFilename,
            onCompletion: handleFileExport
        )
        .onChange(of: isShowingFileImporter) { _, isPresented in
            if !isPresented {
                finishFileImporterPresentation()
            }
        }
        .onChange(of: isShowingFileExporter) { _, isPresented in
            if !isPresented {
                finishFileExporterPresentation()
            }
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("حسنًا"))
            )
        }
        .onChange(of: session.resultMessage) { message in
            guard let message else { return }
            alert = VaultBackupAlert(title: "تمت الاستعادة", message: message)
            session.resultMessage = nil
        }
    }

    private func summaryRow(_ title: String, value: Int) -> some View {
        LabeledContent(title) {
            Text("\(value)")
                .fontWeight(.semibold)
        }
    }

    private func securityRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundColor(.secondary)
        }
    }

    private var ownerVerificationTitle: String {
        switch pendingSensitiveAction {
        case .createBackup:
            return "إنشاء نسخة احتياطية"
        case .replaceAll:
            return "استبدال جميع الحسابات"
        case nil:
            return "التحقق الأمني"
        }
    }

    private var ownerVerificationReason: String {
        switch pendingSensitiveAction {
        case .createBackup:
            return "تحقق للسماح بتصدير بيانات VaultX في ملف مشفر"
        case .replaceAll:
            return "تحقق للسماح باستبدال جميع حسابات VaultX"
        case nil:
            return "تحقق لتنفيذ الإجراء الآمن"
        }
    }

    private func requestOwnerVerification(for action: BackupSensitiveAction) {
        pendingSensitiveAction = action
        isShowingOwnerVerification = true
    }

    private func ownerVerificationSucceeded() {
        switch pendingSensitiveAction {
        case .createBackup:
            isShowingCreatePassword = true
        case .replaceAll:
            isShowingReplaceConfirmation = true
        case nil:
            break
        }
        pendingSensitiveAction = nil
    }

    private func createEncryptedBackup(password: String) {
        session.isBusy = true
        Task {
            do {
                let data = try await cryptoService.createBackup(
                    accounts: store.accounts,
                    appVersion: appVersionText,
                    password: password
                )
                exportDocument = VaultBackupDocument(data: data)
                exportFilename = defaultBackupFilename
                session.isBusy = false
                appState.beginTrustedSystemPresentation()
                isFileExporterPresentationActive = true
                isShowingFileExporter = true
            } catch {
                session.isBusy = false
                showError(error)
            }
        }
    }

    private func chooseBackupFile() {
        appState.beginTrustedSystemPresentation()
        isFileImporterPresentationActive = true
        isShowingFileImporter = true
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        finishFileImporterPresentation()

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            readBackupFile(from: url)
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                showError(error)
            }
        }
    }

    private func readBackupFile(from url: URL) {
        session.isBusy = true
        let accessed = url.startAccessingSecurityScopedResource()

        Task {
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard values.isRegularFile != false else {
                        throw VaultBackupError.fileReadFailed
                    }
                    if let size = values.fileSize,
                       size > VaultBackupCryptoService.maximumFileSize {
                        throw VaultBackupError.fileTooLarge
                    }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard data.count <= VaultBackupCryptoService.maximumFileSize else {
                        throw VaultBackupError.fileTooLarge
                    }
                    return data
                }.value

                session.prepare(
                    encryptedData: data,
                    filename: url.lastPathComponent
                )
                session.isBusy = false
                isShowingDecryptPassword = true
            } catch {
                session.isBusy = false
                showError(error)
            }
        }
    }

    private func decryptSelectedBackup(password: String) {
        guard let encryptedData = session.encryptedFileData else {
            showError(VaultBackupError.invalidBackupFile)
            return
        }

        session.isBusy = true
        Task {
            do {
                let payload = try await cryptoService.decryptBackup(
                    encryptedData,
                    password: password
                )
                session.setDecryptedPayload(
                    payload,
                    currentAccounts: store.accounts
                )
                session.isBusy = false
            } catch {
                session.isBusy = false
                showError(error)
            }
        }
    }

    private func replaceAllAccounts() {
        guard let payload = session.payload, !payload.accounts.isEmpty else {
            showError(VaultBackupError.invalidBackupFile)
            return
        }

        let replacement = VaultBackupMergePlanner.replacementAccounts(
            from: payload.accounts
        )
        session.isBusy = true

        Task {
            let result = await store.applyBackupRestore(finalAccounts: replacement)
            session.isBusy = false

            switch result {
            case .success:
                session.reset()
                alert = VaultBackupAlert(
                    title: "تمت الاستعادة",
                    message: "تم استبدال الخزنة واستعادة \(replacement.count) حسابًا بنجاح."
                )
            case .failure:
                alert = VaultBackupAlert(
                    title: "تعذر الاستبدال",
                    message: "بقيت حساباتك الحالية دون تغيير."
                )
            }
        }
    }

    private func handleFileExport(_ result: Result<URL, Error>) {
        finishFileExporterPresentation()

        switch result {
        case .success:
            alert = VaultBackupAlert(
                title: "تم إنشاء النسخة الاحتياطية",
                message: "حُفظ الملف المشفر بنجاح. احتفظ بكلمة مروره في مكان آمن."
            )
        case .failure(let error):
            showError(error)
        }
    }

    private func finishFileImporterPresentation() {
        guard isFileImporterPresentationActive else { return }
        isFileImporterPresentationActive = false
        appState.endTrustedSystemPresentation(lockIfStillBackgrounded: false)
    }

    private func finishFileExporterPresentation() {
        guard isFileExporterPresentationActive else { return }
        isFileExporterPresentationActive = false
        appState.endTrustedSystemPresentation(lockIfStillBackgrounded: false)
        exportDocument = nil
    }

    private func showError(_ error: Error) {
        let message: String
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            message = description
        } else {
            message = "حدث خطأ غير متوقع. حاول مرة أخرى."
        }
        alert = VaultBackupAlert(title: "تعذر إكمال العملية", message: message)
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var defaultBackupFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "VaultX_Backup_\(formatter.string(from: Date()))"
    }
}

private struct BackupPasswordCreationView: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String) -> Void

    @State private var password = ""
    @State private var confirmation = ""
    @State private var isPasswordVisible = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    passwordField("كلمة المرور", text: $password)
                    passwordField("تأكيد كلمة المرور", text: $confirmation)
                } header: {
                    Text("حماية الملف")
                } footer: {
                    Text("استخدم 10 أحرف على الأقل. لن يحفظ VaultX كلمة المرور ولن يستطيع استعادتها.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .navigationTitle("كلمة مرور النسخة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إنشاء") { submit() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func passwordField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Button {
                isPasswordVisible.toggle()
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)

            if isPasswordVisible {
                TextField(title, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                SecureField(title, text: text)
            }
        }
    }

    private func submit() {
        guard password.count >= 10 else {
            errorMessage = "يجب أن تتكون كلمة المرور من 10 أحرف على الأقل."
            return
        }
        guard password == confirmation else {
            errorMessage = "كلمتا المرور غير متطابقتين."
            return
        }

        let submittedPassword = password
        password = ""
        confirmation = ""
        dismiss()
        DispatchQueue.main.async {
            onCreate(submittedPassword)
        }
    }
}

private struct BackupPasswordEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let filename: String
    let onUnlock: (String) -> Void

    @State private var password = ""
    @State private var isPasswordVisible = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(filename)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    HStack {
                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)

                        if isPasswordVisible {
                            TextField("كلمة مرور النسخة", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("كلمة مرور النسخة", text: $password)
                        }
                    }
                } footer: {
                    Text("تُستخدم كلمة المرور لفك الملف محليًا ولا تُحفظ داخل التطبيق.")
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .navigationTitle("فتح النسخة الاحتياطية")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("فتح") { submit() }
                        .disabled(password.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        let submittedPassword = password
        password = ""
        dismiss()
        DispatchQueue.main.async {
            onUnlock(submittedPassword)
        }
    }
}

private struct ReplaceVaultConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    let accountCount: Int
    let onConfirm: () -> Void

    @State private var confirmationText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("سيتم حذف الحسابات الحالية واستبدالها بـ \(accountCount) حسابًا من النسخة.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)

                    TextField("اكتب: استبدال", text: $confirmationText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("تتم العملية في حفظ مشفر واحد. عند فشل الحفظ تبقى الخزنة الحالية دون تغيير.")
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .navigationTitle("تأكيد الاستبدال")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("استبدال", role: .destructive) {
                        dismiss()
                        DispatchQueue.main.async { onConfirm() }
                    }
                    .disabled(confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) != "استبدال")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct VaultBackupReviewView: View {
    @EnvironmentObject private var store: VaultAccountsStore
    @EnvironmentObject private var session: VaultBackupRestoreSession
    @Environment(\.dismiss) private var dismiss

    @State private var alert: VaultBackupAlert?

    var body: some View {
        List {
            Section {
                ForEach($session.reviewItems) { $item in
                    reviewRow(item: $item)
                }
            } header: {
                Text("حدد ما تريد استعادته")
            } footer: {
                Text("الحسابات المتطابقة تُتجاهل تلقائيًا. لا تُستبدل التعارضات دون اختيارك الصريح.")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .navigationTitle("مراجعة الاستعادة")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                applyReviewedRestore()
            } label: {
                HStack {
                    if session.isBusy {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("استعادة المحدد (\(selectedActionCount))")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundColor(.white)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding()
                .background(.bar)
            }
            .buttonStyle(.plain)
            .disabled(selectedActionCount == 0 || session.isBusy || store.isMutationInProgress)
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("حسنًا"))
            )
        }
    }

    @ViewBuilder
    private func reviewRow(item: Binding<VaultBackupReviewItem>) -> some View {
        let value = item.wrappedValue

        VStack(alignment: .trailing, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(value.incomingAccount.serviceName)
                        .font(.headline)
                    Text(accountSubtitle(value.incomingAccount))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                statusBadge(value.status)
            }

            decisionControl(item: item)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func decisionControl(item: Binding<VaultBackupReviewItem>) -> some View {
        switch item.wrappedValue.status {
        case .new:
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                    item.wrappedValue.decision = item.wrappedValue.decision == .add ? .skip : .add
                }
            } label: {
                HStack {
                    Text(item.wrappedValue.decision == .add ? "محدد للاستعادة" : "متجاهل")
                    Spacer()
                    Image(systemName: item.wrappedValue.decision == .add ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(item.wrappedValue.decision == .add ? .accentColor : .secondary)
                }
            }
            .buttonStyle(.plain)

        case .identical:
            Label("موجود مسبقًا — لن يتكرر", systemImage: "checkmark.shield.fill")
                .font(.subheadline)
                .foregroundColor(.secondary)

        case .conflict(let existingID):
            Menu {
                Button("الاحتفاظ بالحساب الحالي") {
                    item.wrappedValue.decision = .skip
                }
                Button("استخدام بيانات النسخة") {
                    item.wrappedValue.decision = .replace(existingID: existingID)
                }
                Button("إنشاء حساب منفصل") {
                    item.wrappedValue.decision = .addSeparate
                }
            } label: {
                decisionMenuLabel(item.wrappedValue.decision)
            }

        case .ambiguous:
            Menu {
                Button("تجاهل") {
                    item.wrappedValue.decision = .skip
                }
                Button("إنشاء حساب منفصل") {
                    item.wrappedValue.decision = .addSeparate
                }
            } label: {
                decisionMenuLabel(item.wrappedValue.decision)
            }
        }
    }

    private func decisionMenuLabel(_ decision: VaultBackupDecision) -> some View {
        HStack {
            Text(decisionText(decision))
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func statusBadge(_ status: VaultBackupReviewStatus) -> some View {
        let presentation: (String, Color) = {
            switch status {
            case .new:
                return ("جديد", .green)
            case .identical:
                return ("موجود", .secondary)
            case .conflict:
                return ("تعارض", .orange)
            case .ambiguous:
                return ("غير واضح", .red)
            }
        }()

        return Text(presentation.0)
            .font(.caption2.bold())
            .foregroundColor(presentation.1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(presentation.1.opacity(0.12))
            .clipShape(Capsule())
    }

    private var selectedActionCount: Int {
        session.reviewItems.filter {
            switch $0.decision {
            case .skip:
                return false
            case .add, .replace, .addSeparate:
                return true
            }
        }.count
    }

    private func applyReviewedRestore() {
        let finalAccounts = VaultBackupMergePlanner.finalAccounts(
            currentAccounts: store.accounts,
            reviewItems: session.reviewItems
        )

        session.isBusy = true
        Task {
            let result = await store.applyBackupRestore(finalAccounts: finalAccounts)
            session.isBusy = false

            switch result {
            case .success:
                let restoredCount = selectedActionCount
                session.reset()
                session.resultMessage = "تم تطبيق \(restoredCount) إجراء استعادة بنجاح."
                dismiss()
            case .failure:
                alert = VaultBackupAlert(
                    title: "تعذر تطبيق الاستعادة",
                    message: "بقيت حساباتك الحالية دون تغيير."
                )
            }
        }
    }

    private func accountSubtitle(_ account: VaultAccount) -> String {
        if !account.email.isEmpty { return account.email }
        if !account.username.isEmpty { return account.username }
        if let issuer = account.totpIssuer, !issuer.isEmpty { return issuer }
        return account.siteURL.isEmpty ? "حساب بدون معرّف" : account.siteURL
    }

    private func decisionText(_ decision: VaultBackupDecision) -> String {
        switch decision {
        case .skip:
            return "الاحتفاظ بالحالي"
        case .add:
            return "استعادة الحساب"
        case .replace:
            return "استخدام بيانات النسخة"
        case .addSeparate:
            return "إنشاء حساب منفصل"
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        VaultBackupRestoreView()
            .environmentObject(VaultAccountsStore.preview())
            .environmentObject(AppLockState.preview(state: .unlocked))
            .environmentObject(VaultBackupRestoreSession())
    }
}
#endif
