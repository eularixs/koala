import SwiftUI

/// Solid-color uppercase badge for ProjectTag. Renders "NO TAG" with secondary
/// gray when input is nil. Used in toolbar + welcome project list.
struct TagBadgeView: View {
    let tag: ProjectTag?
    var compact: Bool = false

    var body: some View {
        Text(displayText)
            .font(badgeFont)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 6 : 10)
            .padding(.vertical, compact ? 2 : 4)
            .background(backgroundColor, in: Capsule())
    }

    private var badgeFont: Font {
        let base: Font = compact ? .system(size: 9) : .caption2
        return base.weight(.bold)
    }

    private var displayText: String {
        (tag?.name ?? "NO TAG").uppercased()
    }

    private var backgroundColor: Color {
        if let tag, let c = Color(hex: tag.colorHex) { return c }
        return Color.secondary
    }
}
