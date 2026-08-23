import SwiftUI

enum WastlyTheme {
    static let paper = Color(red: 247 / 255, green: 244 / 255, blue: 238 / 255)
    static let ink = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
    static let sage = Color(red: 107 / 255, green: 142 / 255, blue: 107 / 255)
    static let apricot = Color(red: 232 / 255, green: 168 / 255, blue: 124 / 255)
    static let hairline = Color.black.opacity(0.08)
    static let muted = Color.black.opacity(0.45)
    static let cardRadius: CGFloat = 18
}

struct PaperBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WastlyTheme.paper.ignoresSafeArea())
    }
}

struct JournalCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: WastlyTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WastlyTheme.cardRadius, style: .continuous)
                    .stroke(WastlyTheme.hairline, lineWidth: 1)
            )
    }
}

extension Font {
    static let wastlyDayTotal = Font.system(size: 40, weight: .semibold, design: .rounded)
    static let wastlyBody = Font.system(size: 16, weight: .regular, design: .rounded)
    static let wastlyCaption = Font.system(size: 13, weight: .regular, design: .rounded)
}
