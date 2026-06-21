import Foundation

enum HeadUpDefaultsKey {
    static let onboardingCompleted = "onboarding.completed"
}

extension Notification.Name {
    static let headUpOnboardingCompleted = Notification.Name("com.king.headup.onboardingCompleted")
}

enum HeadUpLinks {
    static let repository = URL(string: "https://github.com/breezedeus/head-up")!
    static let releases = repository.appending(path: "releases")
    static let issues = repository.appending(path: "issues")
    static let privacy = repository.appending(path: "blob/main/PRIVACY.md")
}

enum HeadUpAppInfo {
    static var versionDescription: String {
        let dictionary = Bundle.main.infoDictionary
        let version = dictionary?["CFBundleShortVersionString"] as? String ?? "开发版"
        guard let build = dictionary?["CFBundleVersion"] as? String, !build.isEmpty else {
            return version
        }
        return "\(version) (\(build))"
    }
}
