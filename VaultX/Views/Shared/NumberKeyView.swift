import SwiftUI

struct NumberKeyView: View {
    let text: String
    let subText: String?
    let action: () -> Void
    let size: CGFloat
    let isDisabled: Bool
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(text)
                    .font(.system(size: size * 0.45, weight: .regular, design: .default))
                    .foregroundColor(isDisabled ? .secondary : .primary)
                
                if let subText = subText {
                    Text(subText)
                        .font(.system(size: size * 0.15, weight: .semibold, design: .default))
                        .foregroundColor(isDisabled ? .secondary.opacity(0.5) : .primary)
                        .padding(.top, 2)
                } else if text != "" {
                    // Empty space to maintain alignment for keys without subText
                    Text(" ")
                        .font(.system(size: size * 0.15, weight: .semibold, design: .default))
                        .padding(.top, 2)
                }
            }
            .frame(width: size, height: size)
            .background(Color(UIColor.secondarySystemFill).opacity(isDisabled ? 0.5 : 1.0))
            .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Text(text))
        .accessibilityAddTraits(.isKeyboardKey)
        .disabled(isDisabled)
    }
}

#Preview {
    NumberKeyView(text: "5", subText: "J K L", action: {}, size: 75, isDisabled: false)
}
