import SwiftUI

@MainActor
final class VaultNavigationSession: ObservableObject {
  @Published var path: [UUID] = []
  @Published var isMenuPresented = false
  @Published var isShowingGoogleImport = false
}

struct VaultHomeView: View {
  @EnvironmentObject var store: VaultAccountsStore
  @EnvironmentObject private var appState: AppLockState
  @EnvironmentObject private var editorSession: AccountEditorSession
  @EnvironmentObject private var navigationSession: VaultNavigationSession
  @EnvironmentObject private var googleImportSession: GoogleAuthenticatorImportSession
  @State private var accountPendingDeletion: VaultAccount?
  @State private var showingDeleteConfirmation = false

  var body: some View {
    NavigationStack(path: $navigationSession.path) {
      ZStack {
        Color(uiColor: .systemBackground)
          .ignoresSafeArea()

        VStack(spacing: 0) {
          HStack(spacing: 12) {
            Button {
              openMenu()
            } label: {
              Image(systemName: "line.3.horizontal")
                .foregroundColor(.primary)
                .font(.system(size: 20))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("فتح القائمة")

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
          .cornerRadius(12)
          .padding(.horizontal, 16)
          .padding(.top, 16)

          if store.accounts.isEmpty {
            Spacer()

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
                NavigationLink(value: account.id) {
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
                    editorSession.beginEditing(account)
                  } label: {
                    Label("تعديل", systemImage: "pencil")
                  }
                  .tint(.blue)
                  .disabled(store.isMutationInProgress)
                }
                .environment(\.layoutDirection, .leftToRight)
              }

              Color.clear.frame(height: 80)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
          }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .allowsHitTesting(!navigationSession.isMenuPresented)
        .accessibilityHidden(navigationSession.isMenuPresented)
      }
      .overlay(alignment: .bottomTrailing) {
        Button {
          editorSession.beginNewAccount()
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
        .disabled(store.isMutationInProgress || navigationSession.isMenuPresented)
        .padding(.trailing, 24)
        .padding(.bottom, 24)
        .environment(\.layoutDirection, .leftToRight)
      }
      .navigationDestination(for: UUID.self) { accountID in
        if let account = store.accounts.first(where: { $0.id == accountID }) {
          AccountDetailView(account: account)
        } else {
          ProgressView("جاري تحميل الحساب...")
            .environment(\.layoutDirection, .rightToLeft)
        }
      }
    }
    .sheet(isPresented: editorPresentationBinding) {
      AddAccountView()
        .interactiveDismissDisabled(true)
    }
    .sheet(isPresented: googleImportPresentationBinding) {
      GoogleAuthenticatorImportView()
        .environmentObject(googleImportSession)
    }
    .overlay {
      if showingDeleteConfirmation, accountPendingDeletion != nil {
        deleteConfirmationOverlay
      }
    }
    .overlay {
      sideMenuOverlay
    }
    .alert(item: $store.storageAlert) { alert in
      Alert(
        title: Text(alert.title), message: Text(alert.message),
        dismissButton: .default(Text("حسناً")))
    }
  }

  private var deleteConfirmationOverlay: some View {
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
              !store.isMutationInProgress
            else { return }

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

  private var sideMenuOverlay: some View {
    GeometryReader { proxy in
      let menuWidth = min(proxy.size.width * 0.86, 360)

      ZStack(alignment: .leading) {
        Color.black.opacity(navigationSession.isMenuPresented ? 0.48 : 0)
          .ignoresSafeArea()
          .contentShape(Rectangle())
          .onTapGesture {
            closeMenu()
          }

        VaultMainMenuView(
          onClose: closeMenu,
          onGoogleAuthenticatorImport: openGoogleAuthenticatorImport
        )
        .frame(width: menuWidth)
        .frame(maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(
          UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 24,
            topTrailingRadius: 24
          )
        )
        .shadow(color: .black.opacity(navigationSession.isMenuPresented ? 0.3 : 0), radius: 24, x: 10, y: 0)
        .offset(x: navigationSession.isMenuPresented ? 0 : -menuWidth)
        .gesture(
          DragGesture(minimumDistance: 20)
            .onEnded { value in
              if value.translation.width < -70 {
                closeMenu()
              }
            }
        )
      }
      .environment(\.layoutDirection, .leftToRight)
      .allowsHitTesting(navigationSession.isMenuPresented)
      .accessibilityHidden(!navigationSession.isMenuPresented)
      .animation(.easeInOut(duration: 0.24), value: navigationSession.isMenuPresented)
    }
    .zIndex(100)
  }

  private func openMenu() {
    withAnimation(.easeOut(duration: 0.24)) {
      navigationSession.isMenuPresented = true
    }
  }

  private func closeMenu() {
    withAnimation(.easeIn(duration: 0.2)) {
      navigationSession.isMenuPresented = false
    }
  }

  private func openGoogleAuthenticatorImport() {
    closeMenu()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
      navigationSession.isShowingGoogleImport = true
    }
  }

  private var googleImportPresentationBinding: Binding<Bool> {
    Binding(
      get: { navigationSession.isShowingGoogleImport },
      set: { isPresented in
        if isPresented {
          navigationSession.isShowingGoogleImport = true
        } else if appState.currentState == .unlocked {
          navigationSession.isShowingGoogleImport = false
        }
      }
    )
  }

  private var editorPresentationBinding: Binding<Bool> {
    Binding(
      get: { editorSession.isPresented },
      set: { isPresented in
        if isPresented {
          editorSession.isPresented = true
        } else if appState.currentState == .unlocked {
          editorSession.cancel()
        }
      }
    )
  }
}

#if DEBUG
  #Preview("Dark Mode") {
    VaultHomeView()
      .environmentObject(VaultAccountsStore.preview())
      .environmentObject(AppLockState.preview(state: .unlocked))
      .environmentObject(AccountEditorSession())
      .environmentObject(VaultNavigationSession())
      .environmentObject(GoogleAuthenticatorImportSession())
      .preferredColorScheme(.dark)
  }

  #Preview("Light Mode") {
    VaultHomeView()
      .environmentObject(VaultAccountsStore.preview())
      .environmentObject(AppLockState.preview(state: .unlocked))
      .environmentObject(AccountEditorSession())
      .environmentObject(VaultNavigationSession())
      .environmentObject(GoogleAuthenticatorImportSession())
      .preferredColorScheme(.light)
  }

  #Preview("Small iPhone") {
    VaultHomeView()
      .environmentObject(VaultAccountsStore.preview())
      .environmentObject(AppLockState.preview(state: .unlocked))
      .environmentObject(AccountEditorSession())
      .environmentObject(VaultNavigationSession())
      .environmentObject(GoogleAuthenticatorImportSession())
      .previewDevice(PreviewDevice(rawValue: "iPhone SE (3rd generation)"))
  }

  #Preview("With 2 Accounts") {
    VaultHomeView()
      .environmentObject(
        VaultAccountsStore.preview(accounts: [
          VaultAccount(
            siteURL: "google.com", email: "user@gmail.com", password: "", username: "", notes: "",
            has2FA: true),
          VaultAccount(
            siteURL: "", email: "", password: "", username: "user@microsoft.com", notes: "",
            has2FA: false),
        ])
      )
      .environmentObject(AppLockState.preview(state: .unlocked))
      .environmentObject(AccountEditorSession())
      .environmentObject(VaultNavigationSession())
      .environmentObject(GoogleAuthenticatorImportSession())
      .preferredColorScheme(.dark)
  }
#endif
