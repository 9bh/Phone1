import SwiftUI

class VaultAccountsStore: ObservableObject {
    @Published var accounts: [VaultAccount]
    
    init(accounts: [VaultAccount] = []) {
        self.accounts = accounts
    }
    
    func addAccount(_ account: VaultAccount) {
        accounts.append(account)
    }
    
    func updateAccount(_ account: VaultAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        }
    }
    
    func deleteAccount(id: UUID) {
        accounts.removeAll(where: { $0.id == id })
    }
}
