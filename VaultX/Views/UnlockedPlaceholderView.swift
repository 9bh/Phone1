import SwiftUI

struct UnlockedPlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("VaultX Unlocked")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Your secrets are accessible.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#if DEBUG
#Preview {
    UnlockedPlaceholderView()
        .environmentObject(AppLockState.preview(state: .unlocked))
}
#endif
