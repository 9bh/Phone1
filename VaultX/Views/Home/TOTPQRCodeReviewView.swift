import SwiftUI

struct TOTPQRCodeReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let scannedAccount: ScannedTOTPAccount
    let isDuplicate: Bool
    let onUse: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .trailing, spacing: 18) {
                    Image(systemName: isDuplicate ? "exclamationmark.triangle.fill" : "qrcode.viewfinder")
                        .font(.system(size: 42))
                        .foregroundColor(isDuplicate ? .orange : .accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)

                    Text(isDuplicate ? "الحساب موجود مسبقًا" : "راجع بيانات المصادقة")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Text(
                        isDuplicate
                            ? "يوجد حساب محفوظ يحمل المفتاح السري نفسه، لذلك لن تتم إضافته مرة أخرى."
                            : "تحقق من البيانات المستخرجة من رمز QR قبل استخدامها في الحساب."
                    )
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    VStack(spacing: 0) {
                        reviewRow(label: "اسم الحساب", value: scannedAccount.accountName)
                        Divider()
                        reviewRow(
                            label: "الجهة المصدرة",
                            value: scannedAccount.issuer.isEmpty ? "غير محددة" : scannedAccount.issuer
                        )
                        Divider()
                        reviewRow(label: "المفتاح", value: scannedAccount.maskedSecret)
                        Divider()
                        reviewRow(label: "الخوارزمية", value: scannedAccount.algorithm.rawValue.uppercased())
                        Divider()
                        reviewRow(label: "عدد الخانات", value: "\(scannedAccount.digits)")
                        Divider()
                        reviewRow(label: "الفترة", value: "\(scannedAccount.period) ثانية")
                    }
                    .padding(.horizontal, 16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text("تتم معالجة البيانات محليًا داخل الجهاز، ولا يتم إرسال رمز QR أو المفتاح إلى أي خادم.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Button {
                        onUse()
                        dismiss()
                    } label: {
                        Text("استخدام هذه البيانات")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDuplicate)

                    Button("إلغاء") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .padding(20)
                .environment(\.layoutDirection, .rightToLeft)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("استيراد TOTP")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func reviewRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(value)
                .font(.body.weight(.medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)

            Spacer()

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 14)
        .environment(\.layoutDirection, .leftToRight)
    }
}
