import Foundation

public enum FinanceError: String, LocalizedError, Sendable {
    case invalidAmount, invalidCurrency, missingSettlement, invalidRate, invalidPayment, invalidDate, invalidRecord, missingRecord, overflow, peerUpgrade, invalidCard, recordChanged
    public var errorDescription: String? { Copy.text("finance.error." + rawValue) }
}

public struct FinanceCurrency: Identifiable, Equatable, Sendable {
    public let code: String
    public let symbol: String
    public let minorDigits: Int
    public var id: String { code }
    public var name: String { Copy.text("finance.currency." + code) }
    private static let baseline: [FinanceCurrency] = [
        .init(code: "CNY", symbol: "¥", minorDigits: 2), .init(code: "USD", symbol: "$", minorDigits: 2),
        .init(code: "EUR", symbol: "€", minorDigits: 2), .init(code: "JPY", symbol: "¥", minorDigits: 0),
        .init(code: "GBP", symbol: "£", minorDigits: 2), .init(code: "HKD", symbol: "HK$", minorDigits: 2),
        .init(code: "KRW", symbol: "₩", minorDigits: 0), .init(code: "SGD", symbol: "S$", minorDigits: 2)
    ]
    public static let supported: [FinanceCurrency] = {
        struct Reference: Decodable { var currencies: [Item] }
        struct Item: Decodable { var code: String; var symbol: String; var minorDigits: Int }
        guard let url = TogetherResources.bundle.url(forResource: "FinanceCurrencies", withExtension: "json"), let data = try? Data(contentsOf: url), let reference = try? JSONDecoder().decode(Reference.self, from: data) else { return baseline }
        return reference.currencies.map { .init(code: $0.code, symbol: $0.symbol, minorDigits: $0.minorDigits) }
    }()
    public static func find(_ code: String) -> FinanceCurrency? { supported.first { $0.code == code } }
}

public enum FinanceMoney {
    public static let maximumMinor: Int64 = 90_000_000_000_000
    public static func decimal(_ text: String) throws -> Decimal {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 64, value.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let result = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), !result.isNaN else { throw FinanceError.invalidAmount }
        return result
    }
    public static func minor(_ text: String, currency: String, round: Bool = false) throws -> Int64 {
        guard let code = FinanceCurrency.find(currency) else { throw FinanceError.invalidCurrency }
        var value = try decimal(text), rounded = Decimal()
        NSDecimalRound(&rounded, &value, code.minorDigits, .plain)
        guard round || rounded == value else { throw FinanceError.invalidAmount }
        var scale = Decimal(1); for _ in 0..<code.minorDigits { scale *= 10 }
        let scaled = rounded * scale
        guard scaled >= Decimal(-maximumMinor), scaled <= Decimal(maximumMinor) else { throw FinanceError.overflow }
        return NSDecimalNumber(decimal: scaled).int64Value
    }
    public static func string(_ minor: Int64, currency: String = "CNY") -> String {
        let digits = FinanceCurrency.find(currency)?.minorDigits ?? 2
        if digits == 0 { return String(minor) }
        let magnitude = minor.magnitude
        var scale: UInt64 = 1; for _ in 0..<digits { scale *= 10 }
        let fraction = String(magnitude % scale)
        return (minor < 0 ? "-" : "") + String(magnitude / scale) + "." + String(repeating: "0", count: digits - fraction.count) + fraction
    }
    public static func display(_ minor: Int64, currency: String = "CNY") -> String {
        let symbol = FinanceCurrency.find(currency)?.symbol ?? currency
        return symbol + string(minor, currency: currency) + (currency == "CNY" ? "" : " " + currency)
    }
    public static func sum(_ values: some Sequence<Int64>) throws -> Int64 {
        var result: Int64 = 0
        for value in values { let (next, overflow) = result.addingReportingOverflow(value); guard !overflow else { throw FinanceError.overflow }; result = next }
        return result
    }
}

public struct ExchangeRateSnapshot: Codable, Equatable, Sendable {
    public var cnyPerOriginalUnit: String
    public var source: String
    public var quotedOn: CivilDate
    public init(rate: String, source: String, quotedOn: CivilDate) throws {
        guard try FinanceMoney.decimal(rate) > 0, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              source.count <= 120, quotedOn.isValid else { throw FinanceError.invalidRate }
        cnyPerOriginalUnit = rate; self.source = source; self.quotedOn = quotedOn
    }
}
public enum CNYSettlementBasis: String, Codable, Sendable { case actualCNY, referenceRate }
public struct FinanceAmount: Codable, Equatable, Sendable {
    public var originalMinor: Int64
    public var currencyCode: String
    public var finalCNYMinor: Int64
    public var exchangeRate: ExchangeRateSnapshot?
    public var settlementBasis: CNYSettlementBasis
    public init(original: String, currency: String = "CNY", actualCNY: String? = nil, exchangeRate: ExchangeRateSnapshot? = nil) throws {
        originalMinor = try FinanceMoney.minor(original, currency: currency)
        currencyCode = currency; self.exchangeRate = exchangeRate
        if currency == "CNY" { finalCNYMinor = originalMinor; settlementBasis = .actualCNY }
        else if let actualCNY, !actualCNY.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalCNYMinor = try FinanceMoney.minor(actualCNY, currency: "CNY", round: true); settlementBasis = .actualCNY
        } else if let exchangeRate {
            let value = try FinanceMoney.decimal(original) * FinanceMoney.decimal(exchangeRate.cnyPerOriginalUnit)
            finalCNYMinor = try FinanceMoney.minor(NSDecimalNumber(decimal: value).stringValue, currency: "CNY", round: true); settlementBasis = .referenceRate
        } else { throw FinanceError.missingSettlement }
        guard isValid else { throw FinanceError.invalidAmount }
    }
    public var isValid: Bool {
        guard FinanceCurrency.find(currencyCode) != nil, originalMinor.magnitude <= FinanceMoney.maximumMinor,
              finalCNYMinor.magnitude <= FinanceMoney.maximumMinor,
              (originalMinor >= 0) == (finalCNYMinor >= 0) else { return false }
        if currencyCode == "CNY" && originalMinor != finalCNYMinor { return false }
        if let exchangeRate {
            guard (try? FinanceMoney.decimal(exchangeRate.cnyPerOriginalUnit))?.isNaN == false,
                  ((try? FinanceMoney.decimal(exchangeRate.cnyPerOriginalUnit)) ?? 0) > 0,
                  exchangeRate.quotedOn.isValid, !exchangeRate.source.isEmpty, exchangeRate.source.count <= 120 else { return false }
            if settlementBasis == .referenceRate {
                guard let original = try? FinanceMoney.decimal(FinanceMoney.string(originalMinor, currency: currencyCode)), let rate = try? FinanceMoney.decimal(exchangeRate.cnyPerOriginalUnit),
                      let result = try? FinanceMoney.minor(NSDecimalNumber(decimal: original * rate).stringValue, currency: "CNY", round: true), result == finalCNYMinor else { return false }
            }
        } else if settlementBasis == .referenceRate { return false }
        return true
    }
    private enum CodingKeys: String, CodingKey { case originalMinor, currencyCode, finalCNYMinor, exchangeRate, settlementBasis }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(String(originalMinor), forKey: .originalMinor); try c.encode(currencyCode, forKey: .currencyCode)
        try c.encode(String(finalCNYMinor), forKey: .finalCNYMinor); try c.encodeIfPresent(exchangeRate, forKey: .exchangeRate)
        try c.encode(settlementBasis, forKey: .settlementBasis)
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let original = Int64(try c.decode(String.self, forKey: .originalMinor)), let cny = Int64(try c.decode(String.self, forKey: .finalCNYMinor)) else { throw FinanceError.invalidAmount }
        originalMinor = original; finalCNYMinor = cny; currencyCode = try c.decode(String.self, forKey: .currencyCode)
        exchangeRate = try c.decodeIfPresent(ExchangeRateSnapshot.self, forKey: .exchangeRate); settlementBasis = try c.decode(CNYSettlementBasis.self, forKey: .settlementBasis)
        guard isValid else { throw FinanceError.invalidAmount }
    }
}
