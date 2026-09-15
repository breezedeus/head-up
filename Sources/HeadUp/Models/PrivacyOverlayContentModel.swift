import Foundation

@MainActor
final class PrivacyOverlayContentModel: ObservableObject {
    @Published var weather: WeatherSnapshot?
    @Published var weatherMessageKey: String?
    var weatherText: String? { weather?.displayText ?? weatherMessageKey.map { L10n.text($0) } }
    @Published var weatherSymbol = "cloud.sun.fill"
    @Published var message: String?
}
