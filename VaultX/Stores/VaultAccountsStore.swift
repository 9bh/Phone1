import SwiftUI

enum SecureVaultLoadState: Equatable, Sendable {
    case locked
    case loading
    case loaded
    case failed
}

enum VaultMutationError: Error, Equatable, Sendable {
    case storeNotLoaded
    case mutationInProgress
    case saveFailed
    case commitStateUnknown
}

struct VaultStorageAlert: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class VaultAccountsStore: ObservableObject {
    @Published private(set) var accounts: [VaultAccount] = []
    @Published private(set) var loadState: SecureVaultLoadState = .locked
    @Published private(set) var isMutationInProgress = false
    @Published var storageAlert: VaultStorageAlert?

    private let persistence: any VaultAccountsPersisting
    private var currentSessionGeneration = 0
    private var activeLoadTask: Task<[VaultAccount], Error>?
    private var activeMutationID: UUID?

    init(persistence: any VaultAccountsPersisting) {
        self.persistence = persistence
    }

    func unlockAndLoad() async {
        guard loadState != .loaded, loadState != .loading else { return }

        storageAlert = nil
        loadState = .loading
        currentSessionGeneration += 1
        let session = currentSessionGeneration

        let persistence = self.persistence
        let task = Task {
            try await persistence.loadAccounts()
        }
        activeLoadTask = task

        do {
            let loadedAccounts = try await task.value
            guard !Task.isCancelled,
                  session == currentSessionGeneration,
                  loadState == .loading else {
                return
            }

            accounts = loadedAccounts
            loadState = .loaded
            activeLoadTask = nil
        } catch {
            guard session == currentSessionGeneration,
                  loadState == .loading else {
                return
            }

            accounts = []
            loadState = .failed
            activeLoadTask = nil
        }
    }

    func retryLoad() async {
        guard loadState == .failed else { return }
        storageAlert = nil
        loadState = .locked
        await unlockAndLoad()
    }

    func lockAndClear() {
        currentSessionGeneration += 1
        activeLoadTask?.cancel()
        activeLoadTask = nil
        activeMutationID = nil
        accounts = []
        loadState = .locked
        isMutationInProgress = false
        storageAlert = nil
    }

    func addAccount(_ account: VaultAccount) async -> Result<Void, VaultMutationError> {
        await performMutation { current in
            var modified = current
            modified.append(account)
            return modified
        }
    }

    func updateAccount(_ account: VaultAccount) async -> Result<Void, VaultMutationError> {
        await performMutation { current in
            guard let index = current.firstIndex(where: { $0.id == account.id }) else {
                return current
            }

            var modified = current
            modified[index] = account
            return modified
        }
    }

    func applyGoogleAuthenticatorImport(
        updatedAccounts: [VaultAccount],
        newAccounts: [VaultAccount]
    ) async -> Result<Void, VaultMutationError> {
        var updatesByID: [UUID: VaultAccount] = [:]
        for account in updatedAccounts {
            updatesByID[account.id] = account
        }

        return await performMutation { current in
            var modified = current.map { account in
                updatesByID[account.id] ?? account
            }
            modified.append(contentsOf: newAccounts)
            return modified
        }
    }

    /// Commits an entire restored account set atomically and publishes it only after
    /// the encrypted persistence layer confirms the write.
    func applyBackupRestore(
        finalAccounts: [VaultAccount]
    ) async -> Result<Void, VaultMutationError> {
        guard loadState == .loaded else {
            return .failure(.storeNotLoaded)
        }
        guard activeMutationID == nil else {
            return .failure(.mutationInProgress)
        }
        guard finalAccounts != accounts else {
            return .success(())
        }

        let mutationID = UUID()
        let session = currentSessionGeneration
        let snapshot = accounts

        activeMutationID = mutationID
        isMutationInProgress = true

        do {
            try await persistence.saveAccounts(finalAccounts)

            guard session == currentSessionGeneration,
                  loadState == .loaded else {
                finishMutationIfCurrent(mutationID)
                return .success(())
            }

            accounts = finalAccounts
            finishMutationIfCurrent(mutationID)
            return .success(())
        } catch let persistenceError as VaultPersistenceError
            where persistenceError == .commitStateUnknown
               || persistenceError == .atomicRecoveryFailed {

            guard session == currentSessionGeneration,
                  loadState == .loaded else {
                finishMutationIfCurrent(mutationID)
                return .failure(.commitStateUnknown)
            }

            accounts = []
            loadState = .failed
            storageAlert = VaultStorageAlert(
                title: "تعذر الوصول إلى الخزنة",
                message: "تعذر تأكيد حالة الاستعادة بأمان. لم تُنشر أي بيانات مستعادة. أعد فتح الخزنة للتحقق من حالتها."
            )
            finishMutationIfCurrent(mutationID)
            return .failure(.commitStateUnknown)
        } catch {
            guard session == currentSessionGeneration,
                  loadState == .loaded else {
                finishMutationIfCurrent(mutationID)
                return .failure(.saveFailed)
            }

            accounts = snapshot
            storageAlert = VaultStorageAlert(
                title: "تعذر استعادة النسخة الاحتياطية",
                message: "تعذر حفظ الاستعادة بأمان. بقيت حساباتك الحالية دون تغيير. حاول مرة أخرى."
            )
            finishMutationIfCurrent(mutationID)
            return .failure(.saveFailed)
        }
    }

    func deleteAccount(id: UUID) async -> Result<Void, VaultMutationError> {
        guard loadState == .loaded else {
            return .failure(.storeNotLoaded)
        }
        guard activeMutationID == nil else {
            return .failure(.mutationInProgress)
        }

        let mutationID = UUID()
        let session = currentSessionGeneration
        let snapshot = accounts
        let newAccounts = snapshot.filter { $0.id != id }

        guard newAccounts.count != snapshot.count else {
            return .success(())
        }

        activeMutationID = mutationID
        isMutationInProgress = true

        do {
            // A deletion is published only after the encrypted file confirms the save.
            // This prevents the UI from showing a deletion that was never committed.
            try await persistence.saveAccounts(newAccounts)

            guard session == currentSessionGeneration,
                  loadState == .loaded else {
                finishMutationIfCurrent(mutationID)
                return .success(())
            }

            accounts = newAccounts
            finishMutationIfCurrent(mutationID)
            return .success(())
        } catch let persistenceError as VaultPersistenceError
            where persistenceError == .commitStateUnknown
               || persistenceError == .atomicRecoveryFailed {

            guard session == currentSessionGeneration,
                  loadState == .loaded else {
                finishMutationIfCurrent(mutationID)
                return .failure(.commitStateUnknown)
            }

            accounts = []
            loadState = .failed
            storageAlert = VaultStorageAlert(
                title: "تعذر الوصول إلى الخزنة",
                message: "تعذر تأكيد حالة الحذف بأمان. لم يتم حذف بياناتك. أعد فتح الخزنة للمحاولة مرة أخرى."
            )
            finishMutationIfCurrent(mutationID)
            return .failure(.commitStateUnknown)
        } catch {
            guard session == currentSessionGeneration,
                  loadState == .loaded else {
                finishMutationIfCurrent(mutationID)
                return .failure(.saveFailed)
            }

            // The observable array was never changed, so the account stays visible.
            storageAlert = VaultStorageAlert(
                title: "تعذر حذف الحساب",
                message: "تعذر حفظ الحذف بأمان. بقي الحساب محفوظًا. حاول مرة أخرى."
            )
            finishMutationIfCurrent(mutationID)
            return .failure(.saveFailed)
        }
    }

    private func performMutation(
        _ mutation: ([VaultAccount]) -> [VaultAccount]
    ) async -> Result<Void, VaultMutationError> {
        guard loadState == .loaded else {
            return .failure(.storeNotLoaded)
        }
        guard activeMutationID == nil else {
            return .failure(.mutationInProgress)
        }

        let mutationID = UUID()
        let session = currentSessionGeneration
        let snapshot = accounts
        let newAccounts = mutation(snapshot)

        activeMutationID = mutationID
        isMutationInProgress = true
        accounts = newAccounts

        do {
            try await persistence.saveAccounts(newAccounts)

            guard session == currentSessionGeneration,
                  loadState == .loaded else {
                finishMutationIfCurrent(mutationID)
                return .success(())
            }

            finishMutationIfCurrent(mutationID)
            return .success(())
        } catch let persistenceError as VaultPersistenceError
            where persistenceError == .commitStateUnknown
               || persistenceError == .atomicRecoveryFailed {

            guard session == currentSessionGeneration,
                  loadState == .loaded else {
                finishMutationIfCurrent(mutationID)
                return .failure(.commitStateUnknown)
            }

            accounts = []
            loadState = .failed
            storageAlert = VaultStorageAlert(
                title: "تعذر الوصول إلى الخزنة",
                message: "تعذر تأكيد حالة الحفظ بأمان. لم يتم حذف بياناتك. أعد فتح الخزنة للمحاولة مرة أخرى."
            )
            finishMutationIfCurrent(mutationID)
            return .failure(.commitStateUnknown)
        } catch {
            guard session == currentSessionGeneration,
                  loadState == .loaded else {
                finishMutationIfCurrent(mutationID)
                return .failure(.saveFailed)
            }

            accounts = snapshot
            storageAlert = VaultStorageAlert(
                title: "تعذر حفظ التغييرات",
                message: "تعذر حفظ بيانات الحساب بأمان. لم يتم حذف بياناتك. حاول مرة أخرى."
            )
            finishMutationIfCurrent(mutationID)
            return .failure(.saveFailed)
        }
    }

    private func finishMutationIfCurrent(_ mutationID: UUID) {
        guard activeMutationID == mutationID else { return }
        activeMutationID = nil
        isMutationInProgress = false
    }
}
