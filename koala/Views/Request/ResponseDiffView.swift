import SwiftUI

// MARK: - Diff primitives

enum DiffOp: Hashable {
    case equal(String)
    case insert(String)
    case delete(String)

    var text: String {
        switch self {
        case .equal(let s), .insert(let s), .delete(let s): return s
        }
    }
}

/// Aligned pair of lines for side-by-side rendering. Either side may be nil
/// (representing a blank padding cell).
struct DiffRow: Identifiable, Hashable {
    enum Kind: Hashable { case equal, changed, deleted, inserted }
    let id = UUID()
    let leftLine: String?
    let rightLine: String?
    let kind: Kind
}

enum LineDiff {
    /// Classic O(n*m) LCS diff producing insert/delete/equal ops in order.
    static func diff(_ a: [String], _ b: [String]) -> [DiffOp] {
        let n = a.count
        let m = b.count
        if n == 0 { return b.map { .insert($0) } }
        if m == 0 { return a.map { .delete($0) } }

        // dp[i][j] = LCS length of a[0..<i], b[0..<j]
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0..<n {
            for j in 0..<m {
                if a[i] == b[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        var ops: [DiffOp] = []
        var i = n
        var j = m
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                ops.append(.equal(a[i - 1]))
                i -= 1; j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                ops.append(.delete(a[i - 1]))
                i -= 1
            } else {
                ops.append(.insert(b[j - 1]))
                j -= 1
            }
        }
        while i > 0 { ops.append(.delete(a[i - 1])); i -= 1 }
        while j > 0 { ops.append(.insert(b[j - 1])); j -= 1 }
        return ops.reversed()
    }

    /// Convert ops to aligned rows. Consecutive delete+insert groups are paired
    /// so the visual columns line up.
    static func align(_ ops: [DiffOp]) -> [DiffRow] {
        var rows: [DiffRow] = []
        var i = 0
        while i < ops.count {
            switch ops[i] {
            case .equal(let s):
                rows.append(DiffRow(leftLine: s, rightLine: s, kind: .equal))
                i += 1
            case .delete, .insert:
                var dels: [String] = []
                var ins: [String] = []
                while i < ops.count {
                    if case .delete(let s) = ops[i] { dels.append(s); i += 1 }
                    else { break }
                }
                while i < ops.count {
                    if case .insert(let s) = ops[i] { ins.append(s); i += 1 }
                    else { break }
                }
                let pairs = max(dels.count, ins.count)
                for k in 0..<pairs {
                    let l = k < dels.count ? dels[k] : nil
                    let r = k < ins.count ? ins[k] : nil
                    let kind: DiffRow.Kind
                    if l != nil && r != nil { kind = .changed }
                    else if l != nil { kind = .deleted }
                    else { kind = .inserted }
                    rows.append(DiffRow(leftLine: l, rightLine: r, kind: kind))
                }
            }
        }
        return rows
    }
}

// MARK: - Body formatting

enum DiffBodyFormatter {
    /// Pretty-print as JSON with sorted keys if both inputs parse as JSON.
    /// Otherwise return UTF-8 strings (replacing invalid bytes).
    static func format(left: Data, right: Data) -> (String, String) {
        if let l = prettyJSON(left), let r = prettyJSON(right) {
            return (l, r)
        }
        return (asString(left), asString(right))
    }

    private static func prettyJSON(_ data: Data) -> String? {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
              ),
              let s = String(data: out, encoding: .utf8) else {
            return nil
        }
        return s
    }

    private static func asString(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Header diff

struct HeaderDiffRow: Identifiable, Hashable {
    enum Kind: Hashable { case same, changed, onlyLeft, onlyRight }
    let id = UUID()
    let key: String
    let leftValue: String?
    let rightValue: String?
    let kind: Kind
}

enum HeaderDiff {
    static func diff(left: [String: String], right: [String: String]) -> [HeaderDiffRow] {
        let keys = Set(left.keys).union(right.keys).sorted { $0.lowercased() < $1.lowercased() }
        return keys.map { k in
            let l = left[k]
            let r = right[k]
            let kind: HeaderDiffRow.Kind
            if l == nil { kind = .onlyRight }
            else if r == nil { kind = .onlyLeft }
            else if l != r { kind = .changed }
            else { kind = .same }
            return HeaderDiffRow(key: k, leftValue: l, rightValue: r, kind: kind)
        }
    }
}

// MARK: - View

struct ResponseDiffView: View {
    let left: HistoryEntry
    let right: HistoryEntry

    @Environment(\.dismiss) private var dismiss
    @State private var swapped: Bool = false
    @State private var showHeaderDiff: Bool = false

    private var a: HistoryEntry { swapped ? right : left }
    private var b: HistoryEntry { swapped ? left : right }

    private var bodyRows: [DiffRow] {
        let aData = a.responseSnapshot?.body ?? Data()
        let bData = b.responseSnapshot?.body ?? Data()
        let (aStr, bStr) = DiffBodyFormatter.format(left: aData, right: bData)
        let aLines = aStr.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let bLines = bStr.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return LineDiff.align(LineDiff.diff(aLines, bLines))
    }

    private var headerRows: [HeaderDiffRow] {
        HeaderDiff.diff(
            left: a.responseSnapshot?.headers ?? [:],
            right: b.responseSnapshot?.headers ?? [:]
        )
    }

    private var changedHeaderCount: Int {
        headerRows.filter { $0.kind != .same }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            headerDiffSection
            Divider()
            bodyDiffSection
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 600, idealHeight: 720)
    }

    // MARK: Header bar

    private var header: some View {
        HStack(spacing: 12) {
            sidePill(entry: a, label: "A")
            Button {
                swapped.toggle()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help("Swap sides")
            .buttonStyle(.borderless)
            sidePill(entry: b, label: "B")
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func sidePill(entry: HistoryEntry, label: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if let r = entry.responseSnapshot {
                StatusBadgeView(statusCode: r.statusCode, showText: false)
            } else {
                Text("—")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(entry.requestSnapshot.method.rawValue)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(entry.requestSnapshot.method.color)
            Text(timestamp(entry.sentAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func timestamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: d)
    }

    // MARK: Header diff section

    private var headerDiffSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showHeaderDiff.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showHeaderDiff ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("Headers")
                        .font(.callout.weight(.semibold))
                    Text("\(changedHeaderCount) differ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if showHeaderDiff {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(headerRows) { row in
                            headerRowView(row)
                            Divider().opacity(0.4)
                        }
                    }
                }
                .frame(maxHeight: 160)
                .background(Color.secondary.opacity(0.04))
            }
        }
    }

    private func headerRowView(_ row: HeaderDiffRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(row.key)
                .font(.caption.monospaced().weight(.semibold))
                .frame(width: 200, alignment: .leading)
            Text(row.leftValue ?? "—")
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(2)
                .background(bgForHeaderLeft(row.kind))
            Text(row.rightValue ?? "—")
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(2)
                .background(bgForHeaderRight(row.kind))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .textSelection(.enabled)
    }

    private func bgForHeaderLeft(_ kind: HeaderDiffRow.Kind) -> Color {
        switch kind {
        case .same: return .clear
        case .changed, .onlyLeft: return Color.red.opacity(0.18)
        case .onlyRight: return .clear
        }
    }

    private func bgForHeaderRight(_ kind: HeaderDiffRow.Kind) -> Color {
        switch kind {
        case .same: return .clear
        case .changed, .onlyRight: return Color.green.opacity(0.18)
        case .onlyLeft: return .clear
        }
    }

    // MARK: Body diff section

    private var bodyDiffSection: some View {
        let rows = bodyRows
        return ScrollView([.vertical, .horizontal]) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    bodyRowView(row, lineNumber: idx + 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func bodyRowView(_ row: DiffRow, lineNumber: Int) -> some View {
        HStack(spacing: 0) {
            lineCell(text: row.leftLine, side: .left, kind: row.kind, number: lineNumber)
            Divider()
            lineCell(text: row.rightLine, side: .right, kind: row.kind, number: lineNumber)
        }
        .frame(maxWidth: .infinity)
    }

    private enum Side { case left, right }

    private func lineCell(text: String?, side: Side, kind: DiffRow.Kind, number: Int) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(text == nil ? "" : "\(number)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 38, alignment: .trailing)
            Text(text ?? "")
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(bgForBody(kind: kind, side: side, hasText: text != nil))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bgForBody(kind: DiffRow.Kind, side: Side, hasText: Bool) -> Color {
        if !hasText { return Color.secondary.opacity(0.06) }
        switch (kind, side) {
        case (.equal, _): return .clear
        case (.deleted, .left), (.changed, .left): return Color.red.opacity(0.18)
        case (.inserted, .right), (.changed, .right): return Color.green.opacity(0.18)
        case (.deleted, .right), (.inserted, .left): return .clear
        }
    }
}
