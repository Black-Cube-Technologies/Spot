import SwiftUI

public struct ToastView: View {
    public let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(radius: 6)
            .accessibilityIdentifier("ToastView")
    }
}

public struct ToastHostModifier: ViewModifier {
    @Binding var message: String?
    public init(_ message: Binding<String?>) { self._message = message }
    public func body(content: Content) -> some View {
        ZStack {
            content
            if let msg = message {
                VStack {  ToastView(msg).padding(.top, 24);  Spacer()}
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation { message = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: message != nil)
    }
}

public extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastHostModifier(message))
    }
}
