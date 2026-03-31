import Foundation
import SwiftUI
import Combine

// MARK: - Cell State

enum CellState {
    case empty
    case correct
    case incorrect
}

// MARK: - MathGridModel

@MainActor
class MathGridModel: ObservableObject {

    static let gridSize = 10

    let rowOperands: [Int]
    let colOperands: [Int]
    let correctAnswers: [[Int]]  // correctAnswers[row][col] = row + col

    @Published var userInputs: [[String]]
    @Published var cellStates: [[CellState]]
    @Published var correctCount: Int = 0
    @Published var isCompleted: Bool = false

    var onCompleted: (() -> Void)?

    // MARK: - Init

    init() {
        let n = Self.gridSize
        // 1-9 の数字をランダムに（重複あり）10個生成
        let rows = (0..<n).map { _ in Int.random(in: 1...9) }
        let cols = (0..<n).map { _ in Int.random(in: 1...9) }

        rowOperands = rows
        colOperands = cols
        correctAnswers = rows.map { r in cols.map { c in r + c } }
        userInputs = Array(repeating: Array(repeating: "", count: n), count: n)
        cellStates = Array(repeating: Array(repeating: .empty, count: n), count: n)
    }

    // MARK: - Validation

    func validate(row: Int, col: Int) {
        let input = userInputs[row][col].trimmingCharacters(in: .whitespaces)
        if input.isEmpty {
            if cellStates[row][col] != .empty {
                cellStates[row][col] = .empty
                recalcCount()
            }
            return
        }
        guard let value = Int(input) else {
            cellStates[row][col] = .incorrect
            recalcCount()
            return
        }
        let prev = cellStates[row][col]
        cellStates[row][col] = (value == correctAnswers[row][col]) ? .correct : .incorrect
        if prev != cellStates[row][col] { recalcCount() }
    }

    func validateAll() {
        let n = Self.gridSize
        for r in 0..<n {
            for c in 0..<n {
                validate(row: r, col: c)
            }
        }
    }

    // MARK: - Private

    private func recalcCount() {
        let n = Self.gridSize
        correctCount = (0..<n).reduce(0) { rowAcc, r in
            rowAcc + (0..<n).reduce(0) { colAcc, c in
                colAcc + (cellStates[r][c] == .correct ? 1 : 0)
            }
        }
        if correctCount == n * n && !isCompleted {
            isCompleted = true
            onCompleted?()
        }
    }
}
