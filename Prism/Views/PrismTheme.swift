import SwiftUI

enum PrismTheme {
    static let spectrumColors: [Color] = [
        Color(red: 1.00, green: 0.36, blue: 0.36),
        Color(red: 1.00, green: 0.69, blue: 0.31),
        Color(red: 1.00, green: 0.88, blue: 0.31),
        Color(red: 0.36, green: 1.00, blue: 0.56),
        Color(red: 0.31, green: 0.76, blue: 1.00),
        Color(red: 0.71, green: 0.42, blue: 1.00),
    ]

    static let spectrum = AngularGradient(
        colors: spectrumColors + [spectrumColors[0]],
        center: .center
    )

    static let spectrumBar = LinearGradient(
        colors: spectrumColors,
        startPoint: .leading,
        endPoint: .trailing
    )

    // A stable color per category, drawn from the spectrum.
    static func color(for name: String) -> Color {
        let hash = abs(name.hashValue)
        return spectrumColors[hash % spectrumColors.count]
    }
}

// A simple triangle, used for the in-app Prism mark.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// The Prism logo: a spectrum tile with a white prism triangle.
struct PrismMark: View {
    var size: CGFloat = 56

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(PrismTheme.spectrum)
            .overlay {
                Triangle()
                    .fill(.white)
                    .frame(width: size * 0.40, height: size * 0.34)
                    .shadow(color: .black.opacity(0.15), radius: size * 0.03)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.22), radius: size * 0.07, y: size * 0.03)
    }
}
