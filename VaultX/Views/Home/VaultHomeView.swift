import SwiftUI

@MainActor
final class VaultNavigationSession: ObservableObject {
  @Published var path: [UUID] = []
  @Published var isMenuPresented = false
  @Published var isShowingGoogleImport = false
  @Published var isShowingSecuritySettings = false
}

struct VaultHomeView: View {
  @EnvironmentObject var store: VaultAccountsStore
  @EnvironmentObject private var appState: AppLockState
  @EnvironmentObject private var editorSession: AccountEditorSession
  @EnvironmentObject private var navigationSession: VaultNavigationSession
  @EnvironmentObject private var googleImportSession: GoogleAuthenticatorImportSession
  @Environment(\.scenePhase) private var scenePhase
  @State private var accountPendingDeletion: VaultAccount?
  @State private var showingDeleteConfirmation = false
  @State private var menuDragTranslation: CGFloat = 0
  @State private var isMenuDragging = false

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
        .allowsHitTesting(!navigationSession.isMenuPresented && !isMenuDragging)
        .accessibilityHidden(navigationSession.isMenuPresented || isMenuDragging)
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
      .navigationDestination(isPresented: securitySettingsPresentationBinding) {
        VaultSecuritySettingsView()
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
    .onChange(of: scenePhase) { newPhase in
      if newPhase != .active {
        menuDragTranslation = 0
        isMenuDragging = false
      }
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
      let rawProgress: CGFloat = navigationSession.isMenuPresented
        ? 1 + min(menuDragTranslation, 0) / menuWidth
        : max(menuDragTranslation, 0) / menuWidth
      let presentationProgress = min(max(rawProgress, 0), 1)

      ZStack(alignment: .leading) {
        Color.black.opacity(0.48 * presentationProgress)
          .ignoresSafeArea()
          .contentShape(Rectangle())
          .allowsHitTesting(navigationSession.isMenuPresented || isMenuDragging)
          .onTapGesture {
            closeMenu()
          }

        VaultMainMenuView(
          onClose: closeMenu,
          onGoogleAuthenticatorImport: openGoogleAuthenticatorImport,
          onSecuritySettings: openSecuritySettings
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
        .shadow(color: .black.opacity(0.3 * presentationProgress), radius: 24, x: 10, y: 0)
        .offset(x: -menuWidth * (1 - presentationProgress))
        .allowsHitTesting(navigationSession.isMenuPresented)
        .gesture(
          menuCloseGesture(menuWidth: menuWidth),
          including: navigationSession.isMenuPresented ? .all : .none
        )

        if canOpenMenuFromEdge && !navigationSession.isMenuPresented {
          Color.clear
            .frame(width: 28)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(edgeOpenGesture(menuWidth: menuWidth))
            .accessibilityHidden(true)
        }
      }
      .environment(\.layoutDirection, .leftToRight)
      .accessibilityHidden(!navigationSession.isMenuPresented && !isMenuDragging)
      .animation(.easeInOut(duration: 0.24), value: navigationSession.isMenuPresented)
    }
    .zIndex(100)
  }

  private var canOpenMenuFromEdge: Bool {
    appState.currentState == .unlocked
      && navigationSession.path.isEmpty
      && !navigationSession.isShowingGoogleImport
      && !navigationSession.isShowingSecuritySettings
      && !editorSession.isPresented
      && !showingDeleteConfirmation
  }

  private func edgeOpenGesture(menuWidth: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 3, coordinateSpace: .local)
      .onChanged { value in
        let horizontal = value.translation.width
        let vertical = value.translation.height

        guard horizontal > 0, abs(horizontal) > abs(vertical) else { return }
        isMenuDragging = true
        menuDragTranslation = min(horizontal, menuWidth)
      }
      .onEnded { value in
        guard isMenuDragging else {
          menuDragTranslation = 0
          return
        }

        let projectedWidth = max(value.translation.width, value.predictedEndTranslation.width)
        let shouldOpen = menuDragTranslation >= menuWidth * 0.32
          || projectedWidth >= menuWidth * 0.55

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
          navigationSession.isMenuPresented = shouldOpen
          menuDragTranslation = 0
          isMenuDragging = false
        }
      }
  }

  private func menuCloseGesture(menuWidth: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 3, coordinateSpace: .local)
      .onChanged { value in
        guard navigationSession.isMenuPresented else { return }

        let horizontal = value.translation.width
        let vertical = value.translation.height
        guard horizontal < 0, abs(horizontal) > abs(vertical) else { return }

        isMenuDragging = true
        menuDragTranslation = max(horizontal, -menuWidth)
      }
      .onEnded { value in
        guard isMenuDragging else {
          menuDragTranslation = 0
          return
        }

        let projectedWidth = min(value.translation.width, value.predictedEndTranslation.width)
        let shouldClose = abs(menuDragTranslation) >= menuWidth * 0.32
          || abs(projectedWidth) >= menuWidth * 0.55

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
          navigationSession.isMenuPresented = !shouldClose
          menuDragTranslation = 0
          isMenuDragging = false
        }
      }
  }

  private func openMenu() {
    menuDragTranslation = 0
    isMenuDragging = false
    withAnimation(.easeOut(duration: 0.24)) {
      navigationSession.isMenuPresented = true
    }
  }

  private func closeMenu() {
    menuDragTranslation = 0
    isMenuDragging = false
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

  private func openSecuritySettings() {
    closeMenu()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
      navigationSession.isShowingSecuritySettings = true
    }
  }

  private var securitySettingsPresentationBinding: Binding<Bool> {
    Binding(
      get: { navigationSession.isShowingSecuritySettings },
      set: { isPresented in
        if isPresented {
          navigationSession.isShowingSecuritySettings = true
        } else if appState.currentState == .unlocked {
          navigationSession.isShowingSecuritySettings = false
        }
      }
    )
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
      .environmentObject(VaultSecuritySettings())
      .preferredColorScheme(.dark)
  }

  #Preview("Light Mode") {
    VaultHomeView()
      .environmentObject(VaultAccountsStore.preview())
      .environmentObject(AppLockState.preview(state: .unlocked))
      .environmentObject(AccountEditorSession())
      .environmentObject(VaultNavigationSession())
      .environmentObject(GoogleAuthenticatorImportSession())
      .environmentObject(VaultSecuritySettings())
      .preferredColorScheme(.light)
  }

  #Preview("Small iPhone") {
    VaultHomeView()
      .environmentObject(VaultAccountsStore.preview())
      .environmentObject(AppLockState.preview(state: .unlocked))
      .environmentObject(AccountEditorSession())
      .environmentObject(VaultNavigationSession())
      .environmentObject(GoogleAuthenticatorImportSession())
      .environmentObject(VaultSecuritySettings())
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
      .environmentObject(VaultSecuritySettings())
      .preferredColorScheme(.dark)
  }
#endif
