import AppKit
import DesignSystem
import SyntaxHighlight

/// Tokens de Swift -> cor. Tudo em cores de sistema do AppKit, que adaptam
/// sozinhas a Light/Dark — nada de RGB fixo.
public enum SyntaxTheme {
    public static func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .keyword, .declarationKeyword: .systemPurple
        case .type: .systemTeal
        case .function: .systemBlue
        case .property, .identifier: .labelColor
        case .number: .systemPink
        case .string: .systemRed
        case .comment: .tertiaryLabelColor
        case .docComment: .secondaryLabelColor
        case .attribute: .systemBrown
        case .operatorToken: .secondaryLabelColor
        }
    }

    /// Nomes de declaração em negrito, como o Xcode faz.
    public static func font(for kind: TokenKind, base: NSFont) -> NSFont {
        switch kind {
        case .declarationKeyword, .type, .function, .property:
            NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        default:
            base
        }
    }

    /// Aplica os tokens ao `NSTextStorage`.
    ///
    /// Só recebe `changedRange`: reaplicar o arquivo inteiro a cada tecla
    /// derruba a digitação e faz o realce piscar.
    public static func apply(
        _ lines: [LineTokens],
        lineStarts: [Int],
        changedRange: Range<Int>,
        to storage: NSTextStorage,
        baseFont: NSFont
    ) {
        guard !changedRange.isEmpty else { return }

        for lineIndex in changedRange {
            guard lineIndex >= 0, lineIndex < lines.count, lineIndex < lineStarts.count else { continue }
            let start = lineStarts[lineIndex]
            let end = lineIndex + 1 < lineStarts.count ? lineStarts[lineIndex + 1] - 1 : storage.length
            guard start <= end, end <= storage.length else { continue }
            let lineRange = NSRange(location: start, length: max(end - start, 0))
            guard lineRange.length > 0 else { continue }

            storage.beginEditing()
            storage.setAttributes(baseAttributes(baseFont: baseFont), range: lineRange)

            for token in lines[lineIndex].tokens {
                let range = NSRange(location: start + token.range.lowerBound, length: token.range.count)
                guard NSMaxRange(range) <= NSMaxRange(lineRange) else { continue }
                storage.addAttribute(.foregroundColor, value: color(for: token.kind), range: range)
                storage.addAttribute(.font, value: font(for: token.kind, base: baseFont), range: range)
            }
            storage.endEditing()
        }
    }

    public static func baseAttributes(baseFont: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: makeParagraphStyle(),
        ]
    }

    /// Função em vez de `static let`: `NSParagraphStyle` não é `Sendable`,
    /// então um global estático é erro de concorrência no Swift 6.
    private static func makeParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.defaultTabInterval = 4 * Metrics.unit
        return style
    }
}
