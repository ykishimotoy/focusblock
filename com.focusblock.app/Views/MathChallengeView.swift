import SwiftUI

// MARK: - Cell Focus ID

private struct CellID: Hashable {
    let row: Int
    let col: Int
}

// MARK: - MathChallengeView

struct MathChallengeView: View {
    @ObservedObject var model: MathGridModel
    @EnvironmentObject var sessionManager: FocusSessionManager
    @FocusState private var focusedCell: CellID?

    private let cellSize: CGFloat = 44
    private let headerSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー情報
            headerBar

            Divider()

            // グリッド（スクロール可能）
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    // 列ヘッダー行
                    columnHeaderRow

                    // データ行
                    ForEach(0..<10, id: \.self) { row in
                        dataRow(row: row)
                    }
                }
                .padding(12)
            }

            Divider()

            // フッター
            footerBar
        }
        .frame(minWidth: 520, minHeight: 520)
        .onAppear {
            focusedCell = CellID(row: 0, col: 0)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("100マス計算（足し算）")
                    .font(.headline)
                Text("左端の数字 ＋ 上端の数字 の答えを入力してください")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            // 正解数カウンター
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(model.correctCount) / 100")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(model.correctCount == 100 ? .green : .primary)
                Text("正解")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Column Header Row

    private var columnHeaderRow: some View {
        HStack(spacing: 1) {
            // 左上コーナー
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.15))
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            .frame(width: headerSize, height: headerSize)

            ForEach(0..<10, id: \.self) { col in
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.2))
                    Text("\(model.colOperands[col])")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
                .frame(width: cellSize, height: headerSize)
            }
        }
    }

    // MARK: - Data Row

    private func dataRow(row: Int) -> some View {
        HStack(spacing: 1) {
            // 行ヘッダー（左端）
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.2))
                Text("\(model.rowOperands[row])")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            .frame(width: headerSize, height: cellSize)

            // セル × 10
            ForEach(0..<10, id: \.self) { col in
                mathCell(row: row, col: col)
            }
        }
    }

    // MARK: - Math Cell

    private func mathCell(row: Int, col: Int) -> some View {
        let id = CellID(row: row, col: col)
        let state = model.cellStates[row][col]

        return ZStack {
            // 背景
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor(for: state))

            // 入力フィールド
            TextField("", text: binding(row: row, col: col))
                .multilineTextAlignment(.center)
                .font(.system(.body, design: .monospaced))
                .focused($focusedCell, equals: id)
                .onSubmit { advance(from: row, col: col) }
                .onChange(of: model.userInputs[row][col]) { newValue in
                    // 数字以外を除去
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue {
                        model.userInputs[row][col] = filtered
                    }
                    // 2桁入力で自動確定
                    if model.userInputs[row][col].count >= 2 {
                        model.validate(row: row, col: col)
                        if model.cellStates[row][col] == .correct {
                            advance(from: row, col: col)
                        }
                    } else if model.userInputs[row][col].isEmpty {
                        model.validate(row: row, col: col)
                    }
                }
        }
        .frame(width: cellSize, height: cellSize)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor(for: state, focused: focusedCell == id), lineWidth: focusedCell == id ? 2 : 0.5)
        )
    }

    // MARK: - Helpers

    private func binding(row: Int, col: Int) -> Binding<String> {
        Binding(
            get: { model.userInputs[row][col] },
            set: { model.userInputs[row][col] = $0 }
        )
    }

    private func advance(from row: Int, col: Int) {
        model.validate(row: row, col: col)
        let nextCol = (col + 1) % 10
        let nextRow = col == 9 ? row + 1 : row
        if nextRow < 10 {
            focusedCell = CellID(row: nextRow, col: nextCol)
        } else {
            focusedCell = nil
        }
    }

    private func backgroundColor(for state: CellState) -> Color {
        switch state {
        case .empty: return Color(NSColor.controlBackgroundColor)
        case .correct: return Color.green.opacity(0.15)
        case .incorrect: return Color.red.opacity(0.12)
        }
    }

    private func borderColor(for state: CellState, focused: Bool) -> Color {
        if focused { return .accentColor }
        switch state {
        case .empty: return Color(NSColor.separatorColor)
        case .correct: return .green.opacity(0.6)
        case .incorrect: return .red.opacity(0.5)
        }
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            if model.isCompleted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("全問正解！フォーカスを解除しています…")
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            } else {
                Text("残り \(100 - model.correctCount) 問")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
            Spacer()
            Button("全てチェック") {
                model.validateAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
