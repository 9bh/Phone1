import SwiftUI

struct VaultMainMenuView: View {
    @Environment(\.dismiss) private var dismiss

    let onGoogleAuthenticatorImport: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Button {
                    onGoogleAuthenticatorImport()
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .frame(width: 42, height: 42)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("استيراد من Google Authenticator")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .trailing)

                            Text("نقل الحسابات وربطها بحسابات VaultX الحالية")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                VStack(alignment: .trailing, spacing: 8) {
                    Label("يعمل دون إنترنت", systemImage: "wifi.slash")
                    Label("لا تُحفظ صور QR", systemImage: "photo.badge.checkmark")
                    Label("تتم المطابقة داخل الجهاز", systemImage: "lock.shield")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(16)

                Spacer()
            }
            .padding()
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("القائمة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("إغلاق") { dismiss() }
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
