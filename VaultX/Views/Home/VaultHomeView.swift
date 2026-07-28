import SwiftUI

struct VaultHomeView: View {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Image(systemName: "ellipsis")
                        .foregroundColor(.primary)
                        .font(.system(size: 20))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12) // Rounded rectangular background
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
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
            }
            .environment(\.layoutDirection, .rightToLeft) // Ensure RTL layout for Arabic text
            
            // Floating Add Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 60, height: 60) // Minimum 44x44 touch target
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
                .environment(\.layoutDirection, .leftToRight) // Force physical right corner
            }
        }
    }
}

#if DEBUG
#Preview("Dark Mode") {
    VaultHomeView()
        .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    VaultHomeView()
        .preferredColorScheme(.light)
}

#Preview("Small iPhone") {
    VaultHomeView()
        .previewDevice(PreviewDevice(rawValue: "iPhone SE (3rd generation)"))
}
#endif
