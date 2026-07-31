import PhotosUI
import SwiftUI

private enum GoogleAuthenticatorImportStage: Equatable {
    case intro
    case collecting
    case review
    case completed
}

private struct GoogleAuthenticatorImportMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct GoogleAuthenticatorImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: VaultAccountsStore
    @EnvironmentObject private var appState: AppLockState
    @Environment(\.scenePhase) private var scenePhase

    @State private var stage: GoogleAuthenticatorImportStage = .intro
    @State private var collector = GoogleAuthenticatorMigrationCollector()
    @State private var rows: [GoogleAuthenticatorImportRow] = []
    @State private var isShowingScanner = false
    @State private var queuedRawCode: String?
    @State private var resolvingAccount: GoogleAuthenticatorImportedAccount?
    @State private var message: GoogleAuthenticatorImportMessage?
    @State private var importedCount = 0
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingPhotoPicker = false
    @State private var isAwaitingPhotoPickerReturn = false
    @State private var isProcessingPhoto = false

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .intro:
                    introView
                case .collecting:
                    collectingView
                case .review:
                    reviewView
                case .completed:
                    completedView
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("استيراد Google Authenticator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if stage != .completed {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("إلغاء") {
                            clearSensitiveState()
                            dismiss()
                        }
                    }
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .interactiveDismissDisabled(stage == .collecting || store.isMutationInProgress)
        .fullScreenCover(isPresented: $isShowingScanner, onDismiss: processQueuedCode) {
            RawQRCodeScannerScreen(
                title: "استيراد من Google",
                instruction: "امسح رمز التصدير الظاهر في Google Authenticator",
                progressText: scannerProgressText
            ) { rawValue in
                queuedRawCode = rawValue
            }
        }
        .sheet(item: $resolvingAccount) { imported in
            GoogleAuthenticatorResolutionView(
                importedAccount: imported,
                vaultAccounts: store.accounts,
                currentDecision: row(for: imported.id)?.decision ?? .unresolved
            ) { decision in
                setDecision(decision, for: imported.id)
                resolvingAccount = nil
            }
        }
        .alert(item: $message) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("حسنًا"))
            )
        }
        .photosPicker(
            isPresented: $isShowingPhotoPicker,
            selection: $selectedPhoto,
            matching: .images
        )
        .onChange(of: isShowingPhotoPicker) { isPresented in
            guard !isPresented else { return }
            finishTrustedPhotoPickerPresentation()
        }
        .onChange(of: scenePhase) { newPhase in
            guard isAwaitingPhotoPickerReturn else { return }

            if newPhase == .active {
                isAwaitingPhotoPickerReturn = false
                appState.endTrustedSystemPresentation(lockIfStillBackgrounded: false)
            } else if newPhase == .background {
                isAwaitingPhotoPickerReturn = false
                appState.endTrustedSystemPresentation(lockIfStillBackgrounded: true)
            }
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            await processSelectedPhoto(selectedPhoto)
        }
        .onDisappear {
            guard isShowingPhotoPicker || isAwaitingPhotoPickerReturn else { return }
            isShowingPhotoPicker = false
            isAwaitingPhotoPickerReturn = false
            appState.endTrustedSystemPresentation(
                lockIfStillBackgrounded: scenePhase == .background
            )
        }
    }

    private var introView: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 62, weight: .medium))
                    .foregroundColor(.accentColor)
                    .padding(.top, 24)

                VStack(spacing: 10) {
                    Text("نقل حسابات المصادقة")
                        .font(.title2.bold())

                    Text("من Google Authenticator افتح نقل الحسابات، اختر تصدير الحسابات، ثم امسح رمز QR هنا.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .trailing, spacing: 14) {
                    instructionRow(number: "1", text: "افتح Google Authenticator.")
                    instructionRow(number: "2", text: "اختر نقل الحسابات ثم تصدير الحسابات.")
                    instructionRow(number: "3", text: "حدّد الحسابات واعرض رمز QR.")
                    instructionRow(number: "4", text: "امسح جميع الأجزاء إذا ظهر أكثر من رمز.")
                }
                .padding(18)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .trailing, spacing: 8) {
                    Label("لا يحتاج اتصالًا بالإنترنت", systemImage: "wifi.slash")
                    Label("لا تُحفظ صور QR أو تُرسل خارج الجهاز", systemImage: "lock.shield")
                    Label("لن يُدمج أي حساب دون عرض النتيجة لك", systemImage: "person.crop.circle.badge.checkmark")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(16)

                VStack(spacing: 12) {
                    Button {
                        beginFreshImport()
                        isShowingScanner = true
                    } label: {
                        Label("مسح من جهاز آخر", systemImage: "camera.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        presentPhotoPicker()
                    } label: {
                        Label("اختيار لقطة شاشة من هذا الآيفون", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessingPhoto || isShowingPhotoPicker)

                    Text("عند النقل على الجهاز نفسه، التقط صورة لرمز التصدير ثم اخترها هنا. احذف اللقطة من الصور بعد اكتمال الاستيراد لأنها تحتوي على مفاتيح المصادقة.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
    }

    private var collectingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 10)
                    .frame(width: 132, height: 132)

                Circle()
                    .trim(from: 0, to: collectionProgress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 132, height: 132)

                VStack(spacing: 4) {
                    Text("\(collector.scannedPartCount)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("من \(max(collector.expectedPartCount, 1))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(spacing: 8) {
                Text(collector.scannedPartCount == 0 ? "بانتظار أول رمز" : "تم حفظ الجزء داخل الذاكرة مؤقتًا")
                    .font(.headline)

                Text("الحسابات المقروءة حتى الآن: \(collector.accounts.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                Button {
                    isShowingScanner = true
                } label: {
                    Label(
                        collector.scannedPartCount == 0 ? "فتح الكاميرا" : "مسح الرمز التالي",
                        systemImage: "qrcode.viewfinder"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    presentPhotoPicker()
                } label: {
                    if isProcessingPhoto {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Label("اختيار لقطة للرمز التالي", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isProcessingPhoto || isShowingPhotoPicker)
            }
            .padding(.horizontal)

            Button("إعادة البدء") {
                collector.reset()
                rows = []
                queuedRawCode = nil
            }
            .foregroundColor(.red)

            Spacer()
        }
        .padding()
    }

    private var reviewView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("مراجعة وربط الحسابات")
                        .font(.headline)
                    Text("اضغط على أي حساب لتغيير طريقة استيراده.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(rows.count)")
                    .font(.title2.bold())
                    .foregroundColor(.accentColor)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(rows) { row in
                        Button {
                            resolvingAccount = row.account
                        } label: {
                            importRowView(row)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }

            VStack(spacing: 10) {
                if unresolvedCount > 0 {
                    Text("يوجد \(unresolvedCount) حساب يحتاج منك اختيار طريقة الربط.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }

                Button {
                    commitImport()
                } label: {
                    if store.isMutationInProgress {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Text("حفظ التغييرات")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(unresolvedCount > 0 || store.isMutationInProgress)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    private var completedView: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.green)

            Text("اكتمل الاستيراد")
                .font(.title2.bold())

            Text("تم حفظ \(importedCount) حساب أو تحديثه داخل الخزنة المشفرة.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("العودة إلى الحسابات") {
                clearSensitiveState()
                dismiss()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor)
                .clipShape(Circle())

            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func importRowView(_ row: GoogleAuthenticatorImportRow) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .trailing, spacing: 7) {
                Text(row.account.displayIssuer)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Text(row.account.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                HStack(spacing: 6) {
                    Image(systemName: decisionIcon(row.decision))
                    Text(decisionTitle(row))
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(decisionColor(row.decision))
                .frame(maxWidth: .infinity, alignment: .trailing)

                if let reason = row.suggestionReason, row.decision == .unresolved {
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            Image(systemName: "chevron.left")
                .font(.caption.bold())
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(row.decision == .unresolved ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
        }
    }

    private var scannerProgressText: String? {
        guard collector.scannedPartCount > 0 else { return nil }
        return "تم مسح \(collector.scannedPartCount) من \(collector.expectedPartCount)"
    }

    private var collectionProgress: Double {
        guard collector.expectedPartCount > 0 else { return 0 }
        return min(1, Double(collector.scannedPartCount) / Double(collector.expectedPartCount))
    }

    private var unresolvedCount: Int {
        rows.filter { $0.decision == .unresolved }.count
    }

    private func processQueuedCode() {
        guard let rawValue = queuedRawCode else { return }
        queuedRawCode = nil
        processRawValue(rawValue)
    }

    private func processRawValue(_ rawValue: String) {
        do {
            let batch = try GoogleAuthenticatorMigrationParser.parse(rawValue)
            try collector.add(batch)

            if collector.isComplete {
                prepareRows()
                stage = .review
            } else {
                stage = .collecting
            }
        } catch let error as GoogleAuthenticatorMigrationError {
            message = GoogleAuthenticatorImportMessage(
                title: "تعذر استيراد الرمز",
                message: error.arabicMessage
            )
        } catch {
            message = GoogleAuthenticatorImportMessage(
                title: "تعذر استيراد الرمز",
                message: "حدث خطأ غير متوقع أثناء قراءة بيانات التصدير."
            )
        }
    }

    private func beginFreshImport() {
        collector.reset()
        rows = []
        queuedRawCode = nil
        stage = .collecting
    }

    private func finishTrustedPhotoPickerPresentation() {
        if scenePhase == .active {
            appState.endTrustedSystemPresentation(lockIfStillBackgrounded: false)
        } else if scenePhase == .background {
            appState.endTrustedSystemPresentation(lockIfStillBackgrounded: true)
        } else {
            isAwaitingPhotoPickerReturn = true
        }
    }

    private func presentPhotoPicker() {
        guard !isShowingPhotoPicker else { return }
        appState.beginTrustedSystemPresentation()
        isShowingPhotoPicker = true
    }

    private func processSelectedPhoto(_ item: PhotosPickerItem) async {
        if stage == .intro {
            beginFreshImport()
        }

        isProcessingPhoto = true
        defer {
            selectedPhoto = nil
            isProcessingPhoto = false
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw QRCodeImageDecoderError.invalidImage
            }
            try Task.checkCancellation()
            let rawValue = try await QRCodeImageDecoder.decodeFirstQRCode(from: data)
            try Task.checkCancellation()
            processRawValue(rawValue)
        } catch let error as QRCodeImageDecoderError {
            let errorMessage: String
            switch error {
            case .invalidImage:
                errorMessage = "تعذر فتح الصورة المحددة."
            case .noQRCodeFound:
                errorMessage = "لم يتم العثور على رمز QR واضح داخل الصورة."
            case .unreadableQRCode:
                errorMessage = "تعذر قراءة رمز QR من الصورة. جرّب لقطة أوضح."
            }
            message = GoogleAuthenticatorImportMessage(
                title: "تعذر قراءة الصورة",
                message: errorMessage
            )
        } catch {
            message = GoogleAuthenticatorImportMessage(
                title: "تعذر قراءة الصورة",
                message: "تعذر تحميل الصورة المحددة من الجهاز."
            )
        }
    }

    private func prepareRows() {
        rows = collector.accounts.map { imported in
            let suggestion = GoogleAuthenticatorAccountMatcher.suggestion(
                for: imported,
                among: store.accounts
            )

            let decision: GoogleAuthenticatorImportDecision
            switch suggestion.strength {
            case .alreadyImported:
                decision = .skip
            case .strong:
                if let accountID = suggestion.accountID,
                   let account = store.accounts.first(where: { $0.id == accountID }),
                   account.totpSecret?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                    decision = .link(accountID)
                } else {
                    decision = .unresolved
                }
            case .possible:
                decision = .unresolved
            case .none:
                decision = .createNew
            }

            return GoogleAuthenticatorImportRow(
                account: imported,
                decision: decision,
                suggestedAccountID: suggestion.accountID,
                suggestionReason: suggestion.reason
            )
        }
    }

    private func row(for id: UUID) -> GoogleAuthenticatorImportRow? {
        rows.first(where: { $0.id == id })
    }

    private func setDecision(_ decision: GoogleAuthenticatorImportDecision, for id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].decision = decision
    }

    private func decisionTitle(_ row: GoogleAuthenticatorImportRow) -> String {
        switch row.decision {
        case .unresolved:
            return "يحتاج مراجعة"
        case .createNew:
            return "إنشاء حساب جديد"
        case .skip:
            return "لن يتم استيراده"
        case .link(let id):
            return "ربط مع \(accountTitle(id))"
        case .replace(let id):
            return "استبدال رمز التحقق في \(accountTitle(id))"
        }
    }

    private func accountTitle(_ id: UUID) -> String {
        guard let account = store.accounts.first(where: { $0.id == id }) else {
            return "حساب موجود"
        }
        let identity = !account.email.isEmpty ? account.email : account.username
        return identity.isEmpty ? account.serviceName : "\(account.serviceName) — \(identity)"
    }

    private func decisionIcon(_ decision: GoogleAuthenticatorImportDecision) -> String {
        switch decision {
        case .unresolved: return "exclamationmark.triangle.fill"
        case .createNew: return "plus.circle.fill"
        case .skip: return "minus.circle.fill"
        case .link: return "link.circle.fill"
        case .replace: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    private func decisionColor(_ decision: GoogleAuthenticatorImportDecision) -> Color {
        switch decision {
        case .unresolved: return .orange
        case .skip: return .secondary
        case .createNew, .link: return .green
        case .replace: return .red
        }
    }

    private func commitImport() {
        guard unresolvedCount == 0, !store.isMutationInProgress else { return }

        var linkedAccountIDs = Set<UUID>()
        for row in rows {
            let targetID: UUID?
            switch row.decision {
            case .link(let id), .replace(let id):
                targetID = id
            default:
                targetID = nil
            }

            if let targetID {
                guard store.accounts.contains(where: { $0.id == targetID }) else {
                    message = GoogleAuthenticatorImportMessage(
                        title: "تعذر إكمال الربط",
                        message: "أحد الحسابات المحددة لم يعد موجودًا. راجع الاختيارات مرة أخرى."
                    )
                    return
                }

                guard linkedAccountIDs.insert(targetID).inserted else {
                    message = GoogleAuthenticatorImportMessage(
                        title: "حساب مرتبط أكثر من مرة",
                        message: "لا يمكن ربط رمزي مصادقة مختلفين بالحساب نفسه في عملية واحدة. اختر حسابًا مختلفًا أو أنشئ بطاقة جديدة."
                    )
                    return
                }
            }
        }

        var updatesByID: [UUID: VaultAccount] = [:]
        var additions: [VaultAccount] = []
        var effectiveCount = 0

        for row in rows {
            switch row.decision {
            case .unresolved:
                return
            case .skip:
                continue
            case .createNew:
                additions.append(makeNewVaultAccount(from: row.account))
                effectiveCount += 1
            case .link(let id), .replace(let id):
                guard var existing = store.accounts.first(where: { $0.id == id }) else { continue }
                apply(row.account, to: &existing)
                updatesByID[id] = existing
                effectiveCount += 1
            }
        }

        if updatesByID.isEmpty && additions.isEmpty {
            importedCount = 0
            clearPayloadOnly()
            stage = .completed
            return
        }

        Task {
            let result = await store.applyGoogleAuthenticatorImport(
                updatedAccounts: Array(updatesByID.values),
                newAccounts: additions
            )

            switch result {
            case .success:
                importedCount = effectiveCount
                clearPayloadOnly()
                stage = .completed
            case .failure:
                message = GoogleAuthenticatorImportMessage(
                    title: "تعذر حفظ الاستيراد",
                    message: store.storageAlert?.message ?? "تعذر حفظ التغييرات بأمان. لم تتغير بياناتك."
                )
            }
        }
    }

    private func apply(_ imported: GoogleAuthenticatorImportedAccount, to account: inout VaultAccount) {
        account.has2FA = true
        account.totpSecret = imported.secret
        account.totpIssuer = imported.issuer
        account.totpAlgorithm = imported.algorithm
        account.totpDigits = imported.digits
        account.totpPeriod = imported.period
    }

    private func makeNewVaultAccount(from imported: GoogleAuthenticatorImportedAccount) -> VaultAccount {
        let identity = imported.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return VaultAccount(
            siteURL: imported.issuer,
            email: identity.contains("@") ? identity : "",
            password: "",
            username: identity.contains("@") ? "" : identity,
            notes: "",
            has2FA: true,
            hasBackupFile: false,
            totpSecret: imported.secret,
            totpIssuer: imported.issuer,
            totpAlgorithm: imported.algorithm,
            totpDigits: imported.digits,
            totpPeriod: imported.period
        )
    }

    private func clearPayloadOnly() {
        collector.reset()
        rows = []
        queuedRawCode = nil
        resolvingAccount = nil
        selectedPhoto = nil
        isProcessingPhoto = false
    }

    private func clearSensitiveState() {
        clearPayloadOnly()
        importedCount = 0
    }
}

private struct GoogleAuthenticatorResolutionView: View {
    @Environment(\.dismiss) private var dismiss

    let importedAccount: GoogleAuthenticatorImportedAccount
    let vaultAccounts: [VaultAccount]
    let currentDecision: GoogleAuthenticatorImportDecision
    let onSelect: (GoogleAuthenticatorImportDecision) -> Void

    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("الحساب المستورد") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(importedAccount.displayIssuer)
                            .font(.headline)
                        Text(importedAccount.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(importedAccount.algorithm.rawValue.uppercased()) • \(importedAccount.digits) خانات • 30 ثانية")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("الاختيار الحالي: \(currentDecisionTitle)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.accentColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Section("إجراء مستقل") {
                    decisionButton(
                        title: "إنشاء حساب جديد",
                        subtitle: "يحفظ رمز المصادقة في بطاقة جديدة دون دمجه.",
                        icon: "plus.circle.fill",
                        color: .green,
                        decision: .createNew
                    )

                    decisionButton(
                        title: "تجاهل هذا الحساب",
                        subtitle: "لن يُحفظ أو يُعدّل أي حساب بسببه.",
                        icon: "minus.circle.fill",
                        color: .secondary,
                        decision: .skip
                    )
                }

                Section("ربط بحساب موجود") {
                    if filteredAccounts.isEmpty {
                        Text("لا توجد حسابات مطابقة للبحث.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filteredAccounts) { account in
                            accountResolutionRow(account)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "ابحث بالبريد أو اسم الخدمة")
            .navigationTitle("طريقة الاستيراد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("إلغاء") { dismiss() }
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
    }

    private var currentDecisionTitle: String {
        switch currentDecision {
        case .unresolved: return "يحتاج مراجعة"
        case .createNew: return "إنشاء حساب جديد"
        case .skip: return "تجاهل الحساب"
        case .link: return "ربط بحساب موجود"
        case .replace: return "استبدال رمز تحقق موجود"
        }
    }

    private var filteredAccounts: [VaultAccount] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return vaultAccounts }
        return vaultAccounts.filter {
            $0.serviceName.lowercased().contains(query)
                || $0.email.lowercased().contains(query)
                || $0.username.lowercased().contains(query)
                || $0.siteURL.lowercased().contains(query)
        }
    }

    private func accountResolutionRow(_ account: VaultAccount) -> some View {
        let importedSecret = TOTPQRCodeParser.normalizeSecret(importedAccount.secret)
        let existingSecret = account.totpSecret.map(TOTPQRCodeParser.normalizeSecret)
        let sameSecret = existingSecret == importedSecret
        let hasExistingTOTP = !(existingSecret?.isEmpty ?? true)

        return VStack(alignment: .trailing, spacing: 10) {
            HStack {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(account.serviceName)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(account.email.isEmpty ? account.username : account.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Image(systemName: account.iconName)
                    .frame(width: 34, height: 34)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(Circle())
            }

            if sameSecret {
                Button {
                    onSelect(.skip)
                } label: {
                    Label("موجود مسبقًا — عدم التكرار", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            } else if hasExistingTOTP {
                Button {
                    onSelect(.replace(account.id))
                } label: {
                    Label("استبدال رمز التحقق الحالي", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Text("هذا الحساب يحتوي على مفتاح مختلف. الاستبدال لا يتم إلا بعد اختيارك لهذا الزر ثم حفظ المجموعة.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            } else {
                Button {
                    onSelect(.link(account.id))
                } label: {
                    Label("ربط رمز التحقق بهذا الحساب", systemImage: "link")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
    }

    private func decisionButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        decision: GoogleAuthenticatorImportDecision
    ) -> some View {
        Button {
            onSelect(decision)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
            }
        }
        .buttonStyle(.plain)
    }
}
