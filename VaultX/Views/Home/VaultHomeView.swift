import SwiftUI

struct VaultHomeView: View {
    @EnvironmentObject var store: VaultAccountsStore
    @State private var showingAddAccount = false
    @State private var accountBeingEdited: VaultAccount?
    @State private var accountPendingDeletion: VaultAccount?
    @State private var showingDeleteConfirmation = false
    
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
                            NavigationLink {
                                AccountDetailView(account: account)
                            } label: {
                                AccountCardView(account: account)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    guard !store.isMutationInProgress else { return }
                                    accountPendingDeletion = account
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("حذف", systemImage: "trash")
                                }
                                .disabled(store.isMutationInProgress)
                                
                                Button {
                                    accountBeingEdited = account
                                } label: {
                                    Label("تعديل", systemImage: "pencil")
                                }
                                .tint(.blue)
                                .disabled(store.isMutationInProgress)
                            }
                            .environment(\.layoutDirection, .leftToRight)
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
            
        }
        .overlay(alignment: .bottomTrailing) {
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
            .frame(width: 60, height: 60)
            .disabled(store.isMutationInProgress)
            .padding(.trailing, 24)
            .padding(.bottom, 24)
            .environment(\.layoutDirection, .leftToRight)
        }
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountView()
        }
        .sheet(item: $accountBeingEdited) { account in
            AddAccountView(accountToEdit: account)
        }
        .overlay {
            if showingDeleteConfirmation, let _ = accountPendingDeletion {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    
                    VStack(alignment: .trailing, spacing: 20) {
                        Text("حذف الحساب")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                        
                        Text("هل أنت متأكد من حذف هذا الحساب؟ لا يمكن التراجع عن هذا الإجراء.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                        
                        HStack(spacing: 16) {
                            Button {
                                accountPendingDeletion = nil
                                showingDeleteConfirmation = false
                            } label: {
                                Text("إلغاء")
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                    .foregroundColor(.primary)
                                    .cornerRadius(10)
                            }
                            
                            Button {
                                guard let account = accountPendingDeletion,
                                      !store.isMutationInProgress else { return }
                                
                                Task {
                                    _ = await store.deleteAccount(id: account.id)
                                    accountPendingDeletion = nil
                                    showingDeleteConfirmation = false
                                }
                            } label: {
                                Text("حذف")
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .disabled(store.isMutationInProgress)
                        }
                        .environment(\.layoutDirection, .rightToLeft)
                        .padding(.top, 8)
                    }
                    .padding(24)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
                    .padding(.horizontal, 32)
                    .environment(\.layoutDirection, .rightToLeft)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeInOut(duration: 0.2), value: showingDeleteConfirmation)
            }
        }
        .alert(item: $store.storageAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("حسناً")))
        }
    }
}

#if DEBUG
#Preview("Dark Mode") {
    VaultHomeView()
        .environmentObject(VaultAccountsStore.preview())
        .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    VaultHomeView()
        .environmentObject(VaultAccountsStore.preview())
        .preferredColorScheme(.light)
}

#Preview("Small iPhone") {
    VaultHomeView()
        .environmentObject(VaultAccountsStore.preview())
        .previewDevice(PreviewDevice(rawValue: "iPhone SE (3rd generation)"))
}

#Preview("With 2 Accounts") {
    VaultHomeView()
        .environmentObject(VaultAccountsStore.preview(accounts: [
            VaultAccount(siteURL: "google.com", email: "user@gmail.com", password: "", username: "", notes: "", has2FA: true),
            VaultAccount(siteURL: "", email: "", password: "", username: "user@microsoft.com", notes: "", has2FA: false)
        ]))
        .preferredColorScheme(.dark)
}
#endif
