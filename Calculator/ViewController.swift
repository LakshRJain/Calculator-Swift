//
//  ViewController.swift
//  Calculator
//
//  Expression-mode calculator: user builds a full expression (e.g. 6*7/2+1)
//  displayed live in the main label; pressing = evaluates it.
//

import UIKit
import AudioToolbox

class ViewController: UIViewController {

    // MARK: - UI

    /// Small label above the display that shows the committed expression after =
    private let historyLabel: UILabel = {
        let label = UILabel()
        label.textColor = .systemGray
        label.font = .systemFont(ofSize: 20, weight: .light)
        label.textAlignment = .right
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Main large label — shows the live expression while typing, result after =
    private let displayLabel: UILabel = {
        let label = UILabel()
        label.text = "0"
        label.textColor = .white
        label.font = .systemFont(ofSize: 52, weight: .light)
        label.textAlignment = .right
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.3
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let mainStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let buttonRows: [[String]] = [
        ["AC", "+/-", "%", "÷"],
        ["7",  "8",  "9",  "×"],
        ["4",  "5",  "6",  "−"],
        ["1",  "2",  "3",  "+"],
        ["0",  ".",  "="]
    ]

    // MARK: - State

    /// The raw expression the user is building, using plain ASCII operators internally
    private var expression = ""
    /// True right after = so the next digit starts a fresh expression
    private var justEvaluated = false
    /// Track the last character type to enforce rules
    private var lastCharIsOperator: Bool {
        guard let last = expression.last else { return false }
        return "+-*/".contains(last)
    }

    // MARK: - Haptics / Sound

    private let feedback = UIImpactFeedbackGenerator(style: .light)
    private let clickSound: SystemSoundID = 1104

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        feedback.prepare()
        setupUI()
        buildButtons()
    }

    // MARK: - Layout

    private func setupUI() {
        view.addSubview(historyLabel)
        view.addSubview(displayLabel)
        view.addSubview(mainStackView)

        NSLayoutConstraint.activate([
            historyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            historyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            historyLabel.bottomAnchor.constraint(equalTo: displayLabel.topAnchor, constant: -6),
            historyLabel.heightAnchor.constraint(equalToConstant: 28),

            displayLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            displayLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            displayLabel.bottomAnchor.constraint(equalTo: mainStackView.topAnchor, constant: -20),
            displayLabel.heightAnchor.constraint(equalToConstant: 100),

            mainStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            mainStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            mainStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            mainStackView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.55)
        ])
    }

    private func buildButtons() {
        for row in buttonRows {
            let hStack = UIStackView()
            hStack.axis = .horizontal
            hStack.spacing = 12
            hStack.distribution = .fillEqually

            for title in row {
                let button = UIButton(type: .system)
                button.setTitle(title, for: .normal)
                styleButton(button, title: title)
                button.layer.cornerRadius = 35
                button.layer.masksToBounds = true
                button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
                hStack.addArrangedSubview(button)
            }

            mainStackView.addArrangedSubview(hStack)
        }
    }

    // MARK: - Button Dispatch

    @objc private func buttonTapped(_ sender: UIButton) {
        guard let title = sender.currentTitle else { return }

        AudioServicesPlaySystemSound(clickSound)
        feedback.impactOccurred()
        animateButton(sender)

        switch title {
            case "0"..."9":          handleDigit(title)
            case ".":                handleDecimal()
            case "+", "−", "×", "÷": handleOperator(title)
            case "=":                handleEquals()
            case "AC":               handleClear()
            case "+/-":              handleToggleSign()
            case "%":                handlePercent()
            default:                 break
        }
    }

    // MARK: - Input Handlers

    private func handleDigit(_ digit: String) {
        if justEvaluated {
            // Start a fresh expression
            expression    = digit
            justEvaluated = false
            historyLabel.text = ""
        } else {
            expression = expression.isEmpty ? digit : expression + digit
        }
        refreshDisplay()
    }

    private func handleDecimal() {
        if justEvaluated {
            expression    = "0."
            justEvaluated = false
            historyLabel.text = ""
            refreshDisplay()
            return
        }

        // Find the last number segment after the last operator
        let segment = lastNumberSegment()

        if segment.contains(".") { return }   // already has a decimal — ignore

        if segment.isEmpty {
            // Nothing after the last operator (or expression is empty): add "0."
            expression += "0."
        } else {
            expression += "."
        }
        refreshDisplay()
    }

    private func handleOperator(_ op: String) {
        let internalOp = toInternal(op)

        if justEvaluated {
            // Continue from the result
            justEvaluated = false
        }

        if expression.isEmpty {
            // Allow starting with a unary minus
            if internalOp == "-" { expression = "-" }
            refreshDisplay()
            return
        }

        if lastCharIsOperator {
            // Replace the last operator instead of appending a second one
            expression.removeLast()
        }

        expression += internalOp
        refreshDisplay()
    }

    private func handleEquals() {
        guard !expression.isEmpty else { return }

        // Trim any trailing operator before evaluating
        if lastCharIsOperator { expression.removeLast() }
        if expression.isEmpty { return }

        let displayExpr = toDisplay(expression)  // for history label

        guard let result = evaluate(expression) else {
            showError()
            return
        }

        let resultStr = formatDouble(result)
        historyLabel.text = "\(displayExpr) ="
        displayLabel.text = resultStr

        // Store result as the new expression so chaining works (e.g. result + 5)
        expression    = plainString(result)
        justEvaluated = true
    }

    private func handleClear() {
        expression    = ""
        justEvaluated = false
        historyLabel.text = ""
        displayLabel.text = "0"
    }

    private func handleToggleSign() {
        // If expression is a single plain number, negate it
        if let value = Double(expression) {
            expression = plainString(-value)
            refreshDisplay()
            return
        }

        // If the expression ends with a number segment, wrap it in -(…)
        // Simple approach: wrap entire expression
        if expression.hasPrefix("-(") && expression.hasSuffix(")") {
            // Already negated — unwrap
            expression = String(expression.dropFirst(2).dropLast())
        } else {
            expression = "-(\(expression))"
        }
        refreshDisplay()
    }

    private func handlePercent() {
        // Append /100 to the current number segment, wrapped in parens for safety
        guard !expression.isEmpty, !lastCharIsOperator else { return }

        let segment = lastNumberSegment()
        guard !segment.isEmpty, let value = Double(segment) else { return }

        let percentValue = value / 100.0
        let prefixCount = expression.count - segment.count
        let prefix = String(expression.prefix(prefixCount))
        expression = prefix + plainString(percentValue)
        refreshDisplay()
    }

    // MARK: - Evaluation

    /// Evaluate an expression string using NSExpression (safe subset).
    private func evaluate(_ raw: String) -> Double? {
            var index = raw.startIndex
            guard let result = parseExpr(raw, &index) else { return nil }
            // Ensure we consumed the entire string
            skipWhitespace(raw, &index)
            guard index == raw.endIndex else { return nil }
            return (result.isNaN || result.isInfinite) ? nil : result
        }
     
        // MARK: Recursive Descent Parser
     
        private func parseExpr(_ s: String, _ i: inout String.Index) -> Double? {
            guard var left = parseTerm(s, &i) else { return nil }
            while i < s.endIndex {
                skipWhitespace(s, &i)
                guard i < s.endIndex else { break }
                let op = s[i]
                if op == "+" || op == "-" {
                    i = s.index(after: i)
                    guard let right = parseTerm(s, &i) else { return nil }
                    left = op == "+" ? left + right : left - right
                } else { break }
            }
            return left
        }
     
        private func parseTerm(_ s: String, _ i: inout String.Index) -> Double? {
            guard var left = parseUnary(s, &i) else { return nil }
            while i < s.endIndex {
                skipWhitespace(s, &i)
                guard i < s.endIndex else { break }
                let op = s[i]
                if op == "*" || op == "/" {
                    i = s.index(after: i)
                    guard let right = parseUnary(s, &i) else { return nil }
                    if op == "/" {
                        guard right != 0 else { return nil }   // division by zero
                        left = left / right
                    } else {
                        left = left * right
                    }
                } else { break }
            }
            return left
        }
     
        private func parseUnary(_ s: String, _ i: inout String.Index) -> Double? {
            skipWhitespace(s, &i)
            guard i < s.endIndex else { return nil }
            if s[i] == "-" {
                i = s.index(after: i)
                guard let val = parsePrimary(s, &i) else { return nil }
                return -val
            }
            if s[i] == "+" {
                i = s.index(after: i)
            }
            return parsePrimary(s, &i)
        }
     
        private func parsePrimary(_ s: String, _ i: inout String.Index) -> Double? {
            skipWhitespace(s, &i)
            guard i < s.endIndex else { return nil }
     
            // Parenthesised sub-expression
            if s[i] == "(" {
                i = s.index(after: i)
                guard let val = parseExpr(s, &i) else { return nil }
                skipWhitespace(s, &i)
                guard i < s.endIndex, s[i] == ")" else { return nil }
                i = s.index(after: i)
                return val
            }
     
            // Number literal
            var numStr = ""
            while i < s.endIndex && (s[i].isNumber || s[i] == ".") {
                numStr.append(s[i])
                i = s.index(after: i)
            }
            return Double(numStr)
        }
     
        private func skipWhitespace(_ s: String, _ i: inout String.Index) {
            while i < s.endIndex && s[i] == " " { i = s.index(after: i) }
        }

    // MARK: - Operator Conversion

    /// Display symbol → internal ASCII operator
    private func toInternal(_ op: String) -> String {
        switch op {
        case "×": return "*"
        case "÷": return "/"
        case "−": return "-"
        default:  return op   // + stays +
        }
    }

    /// Internal ASCII expression → pretty display string
    private func toDisplay(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "*", with: "×")
            .replacingOccurrences(of: "/", with: "÷")
            .replacingOccurrences(of: "-", with: "−")
    }

    // MARK: - Display

    private func refreshDisplay() {
        if expression.isEmpty {
            displayLabel.text = "0"
        } else {
            displayLabel.text = toDisplay(expression)
        }
    }

    private func showError() {
        displayLabel.text    = "Error"
        historyLabel.text    = ""
        expression           = ""
        justEvaluated        = false
    }

    // MARK: - Helpers

    /// Returns the number characters after the last operator in the expression.
    private func lastNumberSegment() -> String {
        let ops: Set<Character> = ["+", "-", "*", "/", "(", ")"]
        var segment = ""
        for ch in expression.reversed() {
            if ops.contains(ch) { break }
            segment = String(ch) + segment
        }
        return segment
    }

    /// Format a Double for display: up to 10 significant fraction digits, grouped.
    private func formatDouble(_ value: Double) -> String {
        // Use up to 10 fraction digits, strip trailing zeros
        let formatter = NumberFormatter()
        formatter.numberStyle           = .decimal
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Plain numeric string for storing back into expression (no commas, no exponent).
    private func plainString(_ value: Double) -> String {
        var s = String(format: "%.10f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".")  { s.removeLast() }
        }
        return s
    }

    // MARK: - Styling & Animation

    private func styleButton(_ button: UIButton, title: String) {
        if ["+", "−", "×", "÷", "="].contains(title) {
            button.backgroundColor = .systemOrange
            button.setTitleColor(.white, for: .normal)
        } else if ["AC", "+/-", "%"].contains(title) {
            button.backgroundColor = .systemGray
            button.setTitleColor(.white, for: .normal)
        } else {
            button.backgroundColor = UIColor(red: 51/255, green: 51/255, blue: 51/255, alpha: 1)
            button.setTitleColor(.white, for: .normal)
        }
        button.titleLabel?.font = .systemFont(ofSize: 32, weight: .regular)
    }

    private func animateButton(_ button: UIButton) {
        UIView.animate(withDuration: 0.05, animations: {
            button.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                button.transform = .identity
            }
        }
    }
}
