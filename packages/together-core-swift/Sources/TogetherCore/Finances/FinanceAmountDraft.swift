import Foundation

/// Shared validated editor input. Original quote dates are calendar dates,
/// independent of the Mac's timezone; editing unrelated fields preserves basis.
public struct FinanceAmountDraft {
    public var currency = "CNY"
    public var original = ""
    public var actualCNY = ""
    public var rate = ""
    public var rateSource = ""
    public var rateDate: Date
    public init(_ amount: FinanceAmount? = nil, now: Date = Date()) {
        rateDate = now
        if let amount {
            currency = amount.currencyCode; original = FinanceMoney.string(amount.originalMinor, currency: currency)
            actualCNY = amount.settlementBasis == .actualCNY ? FinanceMoney.string(amount.finalCNYMinor) : ""
            rate = amount.exchangeRate?.cnyPerOriginalUnit ?? ""; rateSource = amount.exchangeRate?.source ?? ""
            if let date = amount.exchangeRate?.quotedOn { rateDate = (try? FinancialCalendar.instant(date, timeZone: "Etc/UTC")) ?? now }
        }
    }
    public mutating func changeCurrency(_ code: String) {
        guard code != currency else { return }
        currency = code; original = ""; actualCNY = ""; rate = ""; rateSource = ""
    }
    public func amount() throws -> FinanceAmount {
        var snapshot: ExchangeRateSnapshot?
        if !rate.isEmpty { snapshot = try .init(rate: rate, source: rateSource.isEmpty ? Copy.text("finance.amount.manualRate") : rateSource, quotedOn: CivilDate(rateDate, timeZone: TimeZone(secondsFromGMT: 0)!)) }
        return try FinanceAmount(original: original, currency: currency, actualCNY: actualCNY, exchangeRate: snapshot)
    }
}
