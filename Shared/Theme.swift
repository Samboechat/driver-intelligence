import SwiftUI

/// Paleta de alto contraste para uso noturno no painel do carro.
enum Theme {
    static let background = Color.black
    static let card = Color(white: 0.10)
    static let cardRaised = Color(white: 0.16)
    static let cardBorder = Color(white: 0.22)
    static let accent = Color(red: 0.18, green: 0.84, blue: 0.45)
    static let warning = Color(red: 1.00, green: 0.78, blue: 0.10)
    static let danger = Color(red: 1.00, green: 0.32, blue: 0.30)
    static let info = Color(red: 0.36, green: 0.68, blue: 1.00)
    static let muted = Color(white: 0.64)
}
