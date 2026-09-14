import Foundation

@MainActor
final class PrivacyOverlayContentModel: ObservableObject {
    @Published var weatherText: String?
    @Published var weatherSymbol = "cloud.sun.fill"
    @Published var message: String?
}
