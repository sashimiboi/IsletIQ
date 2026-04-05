import SwiftUI

struct MarkdownText: View, Equatable {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    static func == (lhs: MarkdownText, rhs: MarkdownText) -> Bool {
        lhs.text == rhs.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let content):
                    Text(parseInline(content))
                        .font(level == 1 ? .body.weight(.bold) : level == 2 ? .subheadline.weight(.bold) : .caption.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 2)

                case .divider:
                    Divider().padding(.vertical, 2)

                case .bullet(let content):
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundStyle(Theme.primary)
                            .frame(width: 12, alignment: .center)
                        Text(parseInline(content))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    }

                case .numbered(let num, let content):
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(num).")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.primary)
                            .frame(width: 18, alignment: .trailing)
                        Text(parseInline(content))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    }

                case .table(let rows):
                    TableView(rows: rows)

                case .paragraph(let content):
                    if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(parseInline(content))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineSpacing(2)
                    }
                }
            }
        }
    }

    // MARK: - Block Types

    enum Block {
        case heading(Int, String)
        case divider
        case bullet(String)
        case numbered(Int, String)
        case table([[String]])
        case paragraph(String)
    }

    // MARK: - Block Parsing

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")

        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("### ") {
                blocks.append(.heading(3, String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(.heading(2, String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                blocks.append(.heading(1, String(trimmed.dropFirst(2))))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                // Table — collect all consecutive pipe rows
                var tableRows: [[String]] = []
                while i < lines.count {
                    let row = lines[i].trimmingCharacters(in: .whitespaces)
                    guard row.hasPrefix("|") && row.hasSuffix("|") else { break }
                    // Skip separator rows (|---|---|)
                    let isSeparator = row.replacingOccurrences(of: "|", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
                        .isEmpty
                    if !isSeparator {
                        let cells = row.split(separator: "|").map {
                            $0.trimmingCharacters(in: .whitespaces)
                        }
                        if !cells.isEmpty { tableRows.append(cells) }
                    }
                    i += 1
                }
                if !tableRows.isEmpty { blocks.append(.table(tableRows)) }
                continue
            } else if let match = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let num = Int(trimmed[trimmed.startIndex..<match.lowerBound].filter(\.isNumber)) ?? 1
                let content = String(trimmed[match.upperBound...])
                blocks.append(.numbered(num, content))
            } else {
                blocks.append(.paragraph(trimmed))
            }

            i += 1
        }

        return blocks
    }

    // MARK: - Inline Parsing

    private func parseInline(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(text)
    }
}

// MARK: - Table View

struct TableView: View {
    let rows: [[String]]

    private var headerRow: [String]? {
        rows.first
    }

    private var dataRows: [[String]] {
        Array(rows.dropFirst())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            if let header = headerRow {
                HStack(spacing: 0) {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                }
                .background(Theme.primary.opacity(0.06))
            }

            // Data rows
            ForEach(Array(dataRows.enumerated()), id: \.offset) { i, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(inlineMarkdown(cell))
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                    }
                }
                .background(i % 2 == 0 ? Color.clear : Theme.muted.opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        if let a = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return a
        }
        return AttributedString(text)
    }
}

#Preview {
    MarkdownText("""
    ## Glucose Analysis

    | Metric | Value | Status |
    |--------|-------|--------|
    | Average | 118 mg/dL | Good |
    | TIR | 94% | Excellent |
    | Low events | 1 | Warning |

    - **Average:** 118 mg/dL
    - **Trend:** Falling

    ---

    ### Recommendations

    1. Pre-bolus **15 minutes** before meals
    2. Consider a *lower carb* breakfast
    """)
    .padding()
}
