import SwiftUI

struct VaultHomeView: View {
    @EnvironmentObject var store: VaultAccountsStore
    @State private var showingAddAccount = false
    @State private var accountBeingEdited: VaultAccount?
    @State private var accountPendingDeletion: VaultAccount?
    @State private var accountBeingViewed: VaultAccount?
    
    var body: some View {
        NavigationStack {
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
                
                
                if store.accounts.isEmpty {
                    Spacer()
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
                    List {
                        ForEach(store.accounts) { account in
                            Button {
                                accountBeingViewed = account
                            } label: {
                                AccountCardView(account: account)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .environment(\.layoutDirection, .leftToRight)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    accountPendingDeletion = account
                                } label: {
                                    Label("حذف", systemImage: "trash")
                                }
                                
                                Button {
                                    accountBeingEdited = account
                                } label: {
                                    Label("تعديل", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        
                        // Spacer for floating button
                        Color.clear.frame(height: 80)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
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
        }
        .navigationDestination(item: $accountBeingViewed) { account in
            AccountDetailView(account: account)
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountView()
        }
        .sheet(item: $accountBeingEdited) { account in
            AddAccountView(accountToEdit: account)
        }
        .alert(item: $accountPendingDeletion) { account in
            Alert(
                title: Text("حذف الحساب"),
                message: Text("هل أنت متأكد من حذف هذا الحساب؟"),
                primaryButton: .destructive(Text("حذف")) {
                    store.deleteAccount(id: account.id)
                },
                secondaryButton: .cancel(Text("إلغاء"))
            )
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
            VaultAccount(siteURL: "google.com", email: "user@gmail.com", password: "", username: "", notes: "", has2FA: true),
            VaultAccount(siteURL: "", email: "", password: "", username: "user@microsoft.com", notes: "", has2FA: false)
        ]))
        .preferredColorScheme(.dark)
}
#endif
