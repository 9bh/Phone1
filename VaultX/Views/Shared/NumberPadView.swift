import SwiftUI

struct NumberPadView: View {
    let onNumberTapped: (String) -> Void
    let onDeleteTapped: () -> Void
    let onFaceIDTapped: (() -> Void)?
    let isFaceIDEnabled: Bool
    let isInputDisabled: Bool
    
    private let padData: [[(String, String?)]] = [
        [("1", nil), ("2", "A B C"), ("3", "D E F")],
        [("4", "G H I"), ("5", "J K L"), ("6", "M N O")],
        [("7", "P Q R S"), ("8", "T U V"), ("9", "W X Y Z")],
        [("", nil), ("0", nil), ("delete", nil)]
    ]
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let availableHeight = geometry.size.height
            
            // Calculate optimal sizes ensuring they stay within bounds and maintain minimum touch target (44)
            let maxKeySizeByWidth = (availableWidth - (30 * 2) - (20 * 2)) / 3
            let maxKeySizeByHeight = (availableHeight - (15 * 3)) / 4
            
            let optimalSize = min(maxKeySizeByWidth, maxKeySizeByHeight, 85)
            let keySize = max(optimalSize, 44) // minimum 44pt touch target
            
            let horizontalSpacing = min((availableWidth - (keySize * 3)) / 2, 30)
            let verticalSpacing = min((availableHeight - (keySize * 4)) / 3, 20)
            
            VStack(spacing: verticalSpacing) {
                ForEach(0..<padData.count, id: \.self) { rowIndex in
                    HStack(spacing: horizontalSpacing) {
                        ForEach(0..<padData[rowIndex].count, id: \.self) { colIndex in
                            let item = padData[rowIndex][colIndex]
                            
                            if item.0 == "delete" {
                                Button(action: onDeleteTapped) {
                                    Image(systemName: "delete.left")
                                        .font(.system(size: keySize * 0.35))
                                        .foregroundColor(isInputDisabled ? .secondary : .primary)
                                        .frame(width: keySize, height: keySize)
                                }
                                .accessibilityLabel("Delete")
                                .accessibilityAddTraits(.isKeyboardKey)
                                .disabled(isInputDisabled)
                            } else if item.0 == "" {
                                if let faceIDAction = onFaceIDTapped, isFaceIDEnabled {
                                    Button(action: faceIDAction) {
                                        Image(systemName: "faceid")
                                            .font(.system(size: keySize * 0.45))
                                            .foregroundColor(isInputDisabled ? .secondary : .primary)
                                            .frame(width: keySize, height: keySize)
                                    }
                                    .accessibilityLabel("Face ID")
                                    .accessibilityAddTraits(.isKeyboardKey)
                                    .disabled(isInputDisabled)
                                } else {
                                    Spacer()
                                        .frame(width: keySize, height: keySize)
                                }
                            } else {
                                NumberKeyView(
                                    text: item.0,
                                    subText: item.1,
                                    action: { onNumberTapped(item.0) },
                                    size: keySize,
                                    isDisabled: isInputDisabled
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

#Preview {
    NumberPadView(
        onNumberTapped: { _ in },
        onDeleteTapped: {},
        onFaceIDTapped: {},
        isFaceIDEnabled: true,
        isInputDisabled: false
    )
}
