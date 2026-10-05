import AppKit
import SwiftUI

/// Métricas de layout. Escala 2/4/8/12/16/20/24 (ver PLAN.md §8).
public enum Metrics {
    public static let gutterWidth: CGFloat = 56
    public static let statusBarHeight: CGFloat = 24
    public static let sidebarMinWidth: CGFloat = 200
    public static let sidebarIdealWidth: CGFloat = 260
    public static let sidebarMaxWidth: CGFloat = 420
    public static let controlCornerRadius: CGFloat = 6
    public static let panelCornerRadius: CGFloat = 10
    public static let unit: CGFloat = 4
}

/// Tipografia. SF Mono é a padrão do Xcode para código.
public enum EditorFont {
    public static let defaultSize: CGFloat = 12

    public static func mono(size: CGFloat = defaultSize, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

/// Tokens de cor. Todos derivados das cores semânticas do macOS —
/// sem RGB hardcoded, para acompanhar Light/Dark automaticamente.
public enum Palette {
    public static var background: Color { Color(nsColor: .textBackgroundColor) }
    public static var gutterBackground: Color { Color(nsColor: .textBackgroundColor) }
    public static var currentLine: Color { Color(nsColor: .selectedContentBackgroundColor).opacity(0.18) }
    public static var selection: Color { Color(nsColor: .selectedContentBackgroundColor) }
    public static var sidebar: Color { Color(nsColor: .windowBackgroundColor) }
    public static var separator: Color { Color(nsColor: .separatorColor) }
    public static var chrome: Color { Color(nsColor: .windowBackgroundColor) }

    /// Laranja da marca Swift, usado só nos ícones de pasta e de arquivo
    /// `.swift`. É a única cor não semântica do app, pedida explicitamente:
    /// identifica a linguagem do workspace de relance. Funciona igual em
    /// Light e Dark, então não quebra o modo escuro.
    public static let swiftOrange = Color(red: 0.941, green: 0.318, blue: 0.220)
    public static let swiftOrangeNS = NSColor(
        calibratedRed: 0.941, green: 0.318, blue: 0.220, alpha: 1
    )
}
