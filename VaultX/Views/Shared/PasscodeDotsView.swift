import SwiftUI

struct PasscodeDotsView: View {
    let length: Int
    let activeCount: Int
    
    var body: some View {
        HStack(spacing: 20) {
            ForEach(0..<length, id: \.self) { index in
                Circle()
                    .fill(index < activeCount ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 16, height: 16)
                    .animation(.spring(), value: activeCount)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(activeCount) of \(length) digits entered"))
    }
}

#Preview {
    VStack(spacing: 40) {
        PasscodeDotsView(length: 6, activeCount: 0)
        PasscodeDotsView(length: 6, activeCount: 3)
        PasscodeDotsView(length: 6, activeCount: 6)
    }
}
