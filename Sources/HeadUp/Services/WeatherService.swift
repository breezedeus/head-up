import Foundation

struct WeatherSnapshot: Equatable {
    let locationName: String
    let temperature: Double
    let unit: String
    let weatherCode: Int
    var description: String { WeatherService.description(for: weatherCode) }
    let symbolName: String

    var displayText: String {
        "\(locationName)  \(temperature.formatted(.number.precision(.fractionLength(0)).locale(L10n.locale)))\(unit)  \(description)"
    }
}

enum WeatherServiceError: LocalizedError {
    case invalidCity
    case cityNotFound
    case invalidResponse

    var errorDescription: String? { L10n.text(localizationKey) }

    var localizationKey: String {
        switch self {
        case .invalidCity: return "请填写城市"
        case .cityNotFound: return "没有找到这个城市"
        case .invalidResponse: return "天气服务暂时不可用"
        }
    }
}

struct WeatherService {
    func currentWeather(for city: String) async throws -> WeatherSnapshot {
        let query = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { throw WeatherServiceError.invalidCity }

        var geocoding = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geocoding.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: L10n.language == .simplifiedChinese ? "zh" : "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let geocodingURL = geocoding.url else { throw WeatherServiceError.invalidCity }
        let (locationData, locationResponse) = try await URLSession.shared.data(from: geocodingURL)
        try validate(locationResponse)
        guard let location = try JSONDecoder().decode(GeocodingResponse.self, from: locationData).results?.first else {
            throw WeatherServiceError.cityNotFound
        }

        var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        forecast.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let forecastURL = forecast.url else { throw WeatherServiceError.invalidResponse }
        let (weatherData, weatherResponse) = try await URLSession.shared.data(from: forecastURL)
        try validate(weatherResponse)
        let decoded = try JSONDecoder().decode(ForecastResponse.self, from: weatherData)

        return WeatherSnapshot(
            locationName: location.name,
            temperature: decoded.current.temperature,
            unit: decoded.currentUnits.temperature,
            weatherCode: decoded.current.weatherCode,
            symbolName: Self.symbolName(for: decoded.current.weatherCode, isDay: decoded.current.isDay == 1)
        )
    }

    static func description(for code: Int, language: AppLanguage = L10n.language) -> String {
        switch code {
        case 0: return L10n.format("晴", language: language)
        case 1: return L10n.format("大部晴朗", language: language)
        case 2: return L10n.format("多云", language: language)
        case 3: return L10n.format("阴", language: language)
        case 45, 48: return L10n.format("雾", language: language)
        case 51, 53, 55: return L10n.format("毛毛雨", language: language)
        case 56, 57: return L10n.format("冻雨", language: language)
        case 61: return L10n.format("小雨", language: language)
        case 63: return L10n.format("中雨", language: language)
        case 65: return L10n.format("大雨", language: language)
        case 66, 67: return L10n.format("冻雨", language: language)
        case 71: return L10n.format("小雪", language: language)
        case 73: return L10n.format("中雪", language: language)
        case 75, 77: return L10n.format("大雪", language: language)
        case 80, 81, 82: return L10n.format("阵雨", language: language)
        case 85, 86: return L10n.format("阵雪", language: language)
        case 95, 96, 99: return L10n.format("雷暴", language: language)
        default: return L10n.format("天气变化", language: language)
        }
    }

    static func symbolName(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "snowflake"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw WeatherServiceError.invalidResponse
        }
    }
}

private struct GeocodingResponse: Decodable {
    let results: [Location]?

    struct Location: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
    }
}

private struct ForecastResponse: Decodable {
    let current: Current
    let currentUnits: CurrentUnits

    enum CodingKeys: String, CodingKey {
        case current
        case currentUnits = "current_units"
    }

    struct Current: Decodable {
        let temperature: Double
        let weatherCode: Int
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    struct CurrentUnits: Decodable {
        let temperature: String

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
        }
    }
}
