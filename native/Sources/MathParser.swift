import Foundation

/// Converts a spoken transcript ("forty two times three plus seven") into a numeric answer
/// with correct order of operations. Pure Swift, no Foundation NSExpression (which gets
/// integer division wrong and has no sqrt/percent handling).
public enum MathParser {

    public struct Result { public let expression: String; public let value: Double }
    public enum ParseError: Error, CustomStringConvertible {
        case empty, badToken(String), unbalanced, unexpected(String), divideByZero
        public var description: String {
            switch self {
            case .empty: return "nothing heard"
            case .badToken(let t): return "didn't understand “\(t)”"
            case .unbalanced: return "unbalanced parentheses"
            case .unexpected(let t): return "unexpected “\(t)”"
            case .divideByZero: return "divide by zero"
            }
        }
    }

    // MARK: - Public

    public static func evaluate(_ spoken: String) throws -> Result {
        let expr = normalize(spoken)
        let tokens = try tokenize(expr)
        guard !tokens.isEmpty else { throw ParseError.empty }
        let rpn = try shuntingYard(tokens)
        let value = try evalRPN(rpn)
        return Result(expression: tokens.map(\.display).joined(separator: " "), value: value)
    }

    public static func format(_ v: Double) -> String {
        if v.isNaN { return "undefined" }
        if v.isInfinite { return v > 0 ? "∞" : "-∞" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 6
        f.minimumFractionDigits = 0
        if abs(v) >= 1e15 || (abs(v) < 1e-6 && v != 0) {
            return String(format: "%.6g", v)
        }
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    // MARK: - Normalization (words -> symbols)

    static let smallNumbers: [String: Int] = [
        "zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90,
    ]
    static let scales: [String: Double] = [
        "hundred": 100, "thousand": 1_000, "k": 1_000, "grand": 1_000,
        "million": 1_000_000, "m": 1_000_000, "mil": 1_000_000,
        "billion": 1_000_000_000, "trillion": 1_000_000_000_000,
    ]

    /// Multi-word phrases replaced first (longest first).
    static let phrases: [(String, String)] = [
        ("to the power of", "^"), ("raised to the", "^"), ("raised to", "^"), ("to the", "^"),
        ("square root of", "sqrt"), ("square root", "sqrt"), ("root of", "sqrt"),
        ("multiplied by", "*"), ("divided by", "/"),
        ("open parenthesis", "("), ("open paren", "("), ("open bracket", "("), ("left paren", "("),
        ("close parenthesis", ")"), ("close paren", ")"), ("close bracket", ")"), ("right paren", ")"),
        ("per cent", "%"), ("percent of", "% *"), ("percent", "%"),
        ("negative", "-"), ("minus", "-"), ("subtract", "-"), ("less", "-"), ("take away", "-"),
        ("plus", "+"), ("add", "+"), ("and", "+"),
        ("times", "*"), ("multiply", "*"), ("by", "*"), ("x", "*"),
        ("over", "/"), ("divide", "/"), ("into", "/"),
        ("squared", "^ 2"), ("cubed", "^ 3"), ("caret", "^"),
        ("equals", ""), ("equal", ""), ("what is", ""), ("what's", ""), ("whats", ""), ("is", ""),
        ("calculate", ""), ("compute", ""), ("the", ""), ("a", ""), ("of", "*"),
        ("dollars", ""), ("dollar", ""), ("bucks", ""), ("cents", ""), ("point", "."), ("dot", "."),
        ("half", "0.5"), ("quarter", "0.25"), ("third", "0.333333333333"),
    ]
    /// Fractions attached to a number: "3 and a half" -> "3.5". Run before `phrases`.
    static let attachedFractions: [(String, String)] = [
        ("and a half", ". 5"), ("and a quarter", ". 25"), ("and three quarters", ". 75"),
        ("and a third", ". 333333333333"), ("and two thirds", ". 666666666667"),
    ]

    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        s = s.replacingOccurrences(of: "×", with: " * ")
        s = s.replacingOccurrences(of: "÷", with: " / ")
        s = s.replacingOccurrences(of: "−", with: " - ")
        s = s.replacingOccurrences(of: "–", with: " - ")
        s = s.replacingOccurrences(of: "$", with: " ")
        s = s.replacingOccurrences(of: "?", with: " ")
        s = s.replacingOccurrences(of: ",", with: "")      // 1,234 -> 1234
        s = s.replacingOccurrences(of: "-", with: " - ")   // "42-3" and "forty-two"
        for sym in ["+", "*", "/", "^", "(", ")", "%", "="] {
            s = s.replacingOccurrences(of: sym, with: " \(sym) ")
        }
        s = s.replacingOccurrences(of: ".", with: " . ")
        // Pad so phrase matching is word-bounded.
        s = " " + s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") + " "
        for (phrase, sym) in attachedFractions + phrases {
            s = s.replacingOccurrences(of: " \(phrase) ", with: " \(sym) ")
            // a phrase can appear twice in a row ("... plus ... plus ...") - loop until stable
            while s.contains(" \(phrase) ") { s = s.replacingOccurrences(of: " \(phrase) ", with: " \(sym) ") }
        }
        // "five - -" from "forty-two" hyphen handling leaves nothing bad; collapse "word - word" for number words
        return collapseNumberWords(s)
    }

    /// Merge runs of number words (and digit groups + scale words) into a single numeric literal.
    static func collapseNumberWords(_ s: String) -> String {
        let words = s.split(separator: " ").map(String.init)
        var out: [String] = []
        var i = 0
        while i < words.count {
            var acc = 0.0, current = 0.0
            var consumed = 0
            var sawNumber = false
            var j = i
            var lastWasScale = false
            var hadDigits = false
            scan: while j < words.count {
                let w = words[j]
                if let n = smallNumbers[w] {
                    if hadDigits && !lastWasScale { break scan }   // "5 3" stays two numbers
                    current += Double(n); sawNumber = true; lastWasScale = false; j += 1; consumed += 1
                } else if let sc = scales[w], sawNumber || (w != "k" && w != "m") {
                    if !sawNumber { current = 1 }
                    if sc >= 1000 { acc += current * sc; current = 0 } else { current *= sc }
                    sawNumber = true; lastWasScale = true; j += 1; consumed += 1
                } else if Double(w) != nil, !sawNumber {
                    current = Double(w)!; sawNumber = true; hadDigits = true; lastWasScale = false; j += 1; consumed += 1
                    // only continue if next is a scale word ("5 million")
                    if j < words.count, scales[words[j]] != nil { continue } else { break scan }
                } else { break scan }
            }
            if sawNumber && consumed > 0 {
                let v = acc + current
                if hadDigits && consumed == 1 { out.append(words[i]) }
                else { out.append(v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v)) }
                i += consumed
            } else {
                out.append(words[i]); i += 1
            }
        }
        // join decimals: "3 . 5" -> "3.5", ". 5" -> "0.5"
        var joined: [String] = []
        var k = 0
        while k < out.count {
            if out[k] == ".", k + 1 < out.count, Double(out[k + 1]) != nil {
                let intPart = (joined.last.flatMap { Double($0) } != nil) ? joined.removeLast() : "0"
                joined.append(intPart + "." + out[k + 1]); k += 2
            } else { joined.append(out[k]); k += 1 }
        }
        return joined.joined(separator: " ")
    }

    // MARK: - Tokenizer

    enum Token: Equatable {
        case num(Double), op(Character), lparen, rparen, percent, sqrt
        var display: String {
            switch self {
            case .num(let v): return MathParser.format(v)
            case .op(let c): return c == "*" ? "×" : c == "/" ? "÷" : String(c)
            case .lparen: return "("
            case .rparen: return ")"
            case .percent: return "%"
            case .sqrt: return "√"
            }
        }
    }

    static func tokenize(_ s: String) throws -> [Token] {
        var tokens: [Token] = []
        for w in s.split(separator: " ").map(String.init) {
            switch w {
            case "+", "-", "*", "/", "^": tokens.append(.op(Character(w)))
            case "(": tokens.append(.lparen)
            case ")": tokens.append(.rparen)
            case "%": tokens.append(.percent)
            case "sqrt": tokens.append(.sqrt)
            case "": continue
            default:
                if let v = Double(w) { tokens.append(.num(v)) }
                else { throw ParseError.badToken(w) }
            }
        }
        // Implicit multiplication: "2 ( 3 + 4 )", ") (", "5 sqrt 9"
        var fixed: [Token] = []
        for t in tokens {
            if let last = fixed.last {
                let lastIsValue: Bool = { if case .num = last { return true }; return last == .rparen || last == .percent }()
                let tStartsValue: Bool = { if case .num = t { return true }; return t == .lparen || t == .sqrt }()
                if lastIsValue && tStartsValue { fixed.append(.op("*")) }
            }
            fixed.append(t)
        }
        return fixed
    }

    // MARK: - Shunting yard

    enum RPN { case num(Double), bin(Character), neg, percent, sqrt }

    static func prec(_ c: Character) -> Int { c == "^" ? 4 : (c == "*" || c == "/") ? 3 : 2 }
    static func rightAssoc(_ c: Character) -> Bool { c == "^" }

    static func shuntingYard(_ tokens: [Token]) throws -> [RPN] {
        var out: [RPN] = []
        var stack: [Token] = []        // ops, parens, sqrt, and a sentinel .op("~") for unary minus
        var expectOperand = true
        for t in tokens {
            switch t {
            case .num(let v):
                out.append(.num(v)); expectOperand = false
            case .percent:
                guard !expectOperand else { throw ParseError.unexpected("%") }
                out.append(.percent)
            case .sqrt:
                stack.append(.sqrt); expectOperand = true
            case .lparen:
                stack.append(.lparen); expectOperand = true
            case .rparen:
                while let top = stack.last, top != .lparen { out.append(try rpn(top)); stack.removeLast() }
                guard stack.popLast() == .lparen else { throw ParseError.unbalanced }
                if stack.last == .sqrt { stack.removeLast(); out.append(.sqrt) }
                expectOperand = false
            case .op(let c):
                if expectOperand {
                    if c == "-" { stack.append(.op("~")); continue }
                    if c == "+" { continue }
                    throw ParseError.unexpected(String(c))
                }
                while let top = stack.last, case .op(let tc) = top,
                      (tc == "~" && c != "^") || prec(tc) > prec(c) || (prec(tc) == prec(c) && !rightAssoc(c)) {
                    out.append(try rpn(top)); stack.removeLast()
                }
                stack.append(.op(c)); expectOperand = true
            }
        }
        while let top = stack.popLast() {
            if top == .lparen { throw ParseError.unbalanced }
            out.append(try rpn(top))
        }
        if expectOperand { throw ParseError.unexpected("end") }
        return out
    }

    static func rpn(_ t: Token) throws -> RPN {
        switch t {
        case .op("~"): return .neg
        case .op(let c): return .bin(c)
        case .sqrt: return .sqrt
        default: throw ParseError.unbalanced
        }
    }

    static func evalRPN(_ rpn: [RPN]) throws -> Double {
        var st: [Double] = []
        for item in rpn {
            switch item {
            case .num(let v): st.append(v)
            case .neg: guard let a = st.popLast() else { throw ParseError.unexpected("-") }; st.append(-a)
            case .sqrt: guard let a = st.popLast() else { throw ParseError.unexpected("√") }; st.append(a.squareRoot())
            case .percent: guard let a = st.popLast() else { throw ParseError.unexpected("%") }; st.append(a / 100)
            case .bin(let c):
                guard let b = st.popLast(), let a = st.popLast() else { throw ParseError.unexpected(String(c)) }
                switch c {
                case "+": st.append(a + b)
                case "-": st.append(a - b)
                case "*": st.append(a * b)
                case "/": if b == 0 { throw ParseError.divideByZero }; st.append(a / b)
                case "^": st.append(pow(a, b))
                default: throw ParseError.unexpected(String(c))
                }
            }
        }
        guard st.count == 1 else { throw ParseError.unexpected("expression") }
        return st[0]
    }
}
