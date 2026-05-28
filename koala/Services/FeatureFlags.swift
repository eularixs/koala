import Foundation

enum FeatureFlags {
    static let proEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return ProcessInfo.processInfo.environment["KOALA_PRO"] == "1"
        #endif
    }()

    static let betaChannel: Bool = {
        return ProcessInfo.processInfo.environment["KOALA_BETA"] == "1"
    }()
}
