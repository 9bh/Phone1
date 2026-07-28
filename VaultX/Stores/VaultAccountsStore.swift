import SwiftUI

class VaultAccountsStore: ObservableObject {
    @Published var accounts: [VaultAccount]
    
    init(accounts: [VaultAccount] = []) {
        self.accounts = accounts
    }
    
    func addAccount(_ account: VaultAccount) {
        accounts.append(account)
    }
}
