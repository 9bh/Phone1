import SwiftUI

struct VaultHomeView: View {
    @EnvironmentObject var store: VaultAccountsStore
    @State private var showingAddAccount = false
    
    var body: some View {
        ZStack {
            // Background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Fake Search Bar
                HStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundColor(.primary)
                        .font(.system(size: 20))
                    
                    Text("بحث في الحسابات")
                        .foregroundColor(.secondary)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                    
                    Image(systemName: "ellipsis")
                        .foregroundColor(.primary)
                        .font(.system(size: 20))
                }
                .environment(\.layoutDirection, .leftToRight)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12) // Rounded rectangular background
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                Spacer()
                
                if store.accounts.isEmpty {
                    // Empty State
                    VStack(spacing: 12) {
                        Text("لا توجد حسابات مضافة حتى الآن")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("اضغط زر الإضافة لإضافة حساب جديد")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.accounts) { account in
                                AccountCardView(account: account)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 80) // Leave space for floating button
                    }
                }
            }
            .environment(\.layoutDirection, .rightToLeft) // Ensure RTL layout for Arabic text
            
            // Floating Add Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        showingAddAccount = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 60, height: 60) // Minimum 44x44 touch target
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
                .environment(\.layoutDirection, .leftToRight) // Force physical right corner
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountView()
        }
    }
}

#if DEBUG
#Preview("Dark Mode") {
    VaultHomeView()
        .environmentObject(VaultAccountsStore())
        .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    VaultHomeView()
        .environmentObject(VaultAccountsStore())
        .preferredColorScheme(.light)
}

#Preview("Small iPhone") {
    VaultHomeView()
        .environmentObject(VaultAccountsStore())
        .previewDevice(PreviewDevice(rawValue: "iPhone SE (3rd generation)"))
}

#Preview("With 2 Accounts") {
    VaultHomeView()
        .environmentObject(VaultAccountsStore(accounts: [
            VaultAccount(siteURL: "google.com", email: "user@gmail.com", password: "", username: "", notes: ""),
            VaultAccount(siteURL: "", email: "", password: "", username: "user@microsoft.com", notes: "")
        ]))
        .preferredColorScheme(.dark)
}
#endif
