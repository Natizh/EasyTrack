import Foundation

enum EURValueSource: String, Codable, CaseIterable {
    case confirmed
    case estimated
    case historical

    var title: String {
        switch self {
        case .confirmed: "Confirmed actual EUR"
        case .estimated: "Indicative EUR estimate"
        case .historical: "Preserved historical EUR"
        }
    }
}

enum CurrencyMetadata {
    static let supportedCodes = ["EUR", "USD", "GBP", "CNY", "JPY", "CHF", "CAD", "AUD", "THB", "KWD"]

    static func exponent(for code: String) -> Int {
        switch code.uppercased() {
        case "JPY": 0
        case "KWD": 3
        default: 2
        }
    }

    static func divisor(for code: String) -> Decimal {
        (0..<exponent(for: code)).reduce(Decimal(1)) { result, _ in result * 10 }
    }
}

enum CurrencyMathError: LocalizedError, Equatable {
    case invalidRate
    case overflow

    var errorDescription: String? {
        switch self {
        case .invalidRate: "The exchange rate is invalid."
        case .overflow: "The converted amount is too large."
        }
    }
}

enum CurrencyMath {
    static func eurMinor(originalMinor: Int64, currency: String, eurPerUnit: Decimal) throws -> Int64 {
        guard eurPerUnit > 0 else { throw CurrencyMathError.invalidRate }
        let original = Decimal(originalMinor) / CurrencyMetadata.divisor(for: currency)
        var value = original * eurPerUnit * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .bankers)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber,
              number.compare(NSDecimalNumber(value: Int64.max)) != .orderedDescending,
              number.compare(NSDecimalNumber(value: Int64.min)) != .orderedAscending else {
            throw CurrencyMathError.overflow
        }
        return number.int64Value
    }
}

struct FXRateQuote: Codable, Equatable, Identifiable {
    var id: String { "\(base)-\(quote)-\(date.isoString)" }
    let base: String
    let quote: String
    let date: LocalDay
    let rate: String
    let provider: String

    var decimalRate: Decimal? { Decimal(string: rate, locale: Locale(identifier: "en_US_POSIX")) }
}

enum FXRateError: LocalizedError {
    case invalidCurrency
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCurrency: "This currency pair is not supported."
        case .unavailable: "No indicative exchange rate is available for this date."
        case .invalidResponse: "The rate service returned an invalid response."
        }
    }
}

actor FrankfurterFXService {
    static let shared = FrankfurterFXService()
    private let defaultsKey = "EasyTrack.FXRateCache.v1"

    func quote(base: String, quote: String = "EUR", date: LocalDay) async throws -> FXRateQuote {
        let base = base.uppercased(), quote = quote.uppercased()
        guard CurrencyMetadata.supportedCodes.contains(base), CurrencyMetadata.supportedCodes.contains(quote),
              base != quote else { throw FXRateError.invalidCurrency }
        if let cached = cached(base: base, quote: quote, date: date) { return cached }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.frankfurter.dev"
        components.path = "/v2/rate/\(base.lowercased())/\(quote.lowercased())"
        components.queryItems = [URLQueryItem(name: "date", value: date.isoString)]
        guard let url = components.url else { throw FXRateError.invalidCurrency }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FXRateError.invalidResponse }
        guard http.statusCode == 200 else {
            if [404, 422].contains(http.statusCode) { throw FXRateError.unavailable }
            throw FXRateError.invalidResponse
        }
        struct Response: Decodable { let date: String; let base: String; let quote: String; let rate: Decimal }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let observed = LocalDay(isoString: decoded.date), decoded.rate > 0 else {
            throw FXRateError.invalidResponse
        }
        let result = FXRateQuote(base: decoded.base.uppercased(), quote: decoded.quote.uppercased(),
            date: observed, rate: NSDecimalNumber(decimal: decoded.rate).stringValue,
            provider: "Frankfurter blended official sources")
        store(result)
        return result
    }

    private func cached(base: String, quote: String, date: LocalDay) -> FXRateQuote? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let values = try? JSONDecoder().decode([FXRateQuote].self, from: data) else { return nil }
        return values.first { $0.base == base && $0.quote == quote && $0.date == date }
    }

    private func store(_ quote: FXRateQuote) {
        let existing = UserDefaults.standard.data(forKey: defaultsKey)
            .flatMap { try? JSONDecoder().decode([FXRateQuote].self, from: $0) } ?? []
        let values = [quote] + existing.filter { $0.id != quote.id }.prefix(127)
        if let data = try? JSONEncoder().encode(Array(values)) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
