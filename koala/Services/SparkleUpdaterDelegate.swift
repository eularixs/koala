import Sparkle

// MARK: - SparkleUpdaterDelegate

/// SPUUpdaterDelegate that switches the appcast feed URL based on the
/// betaChannel feature flag.  If FeatureFlags.betaChannel is true (Pro
/// users who opted in), the beta feed is used; otherwise the stable feed
/// is used.  The SUFeedURL in Info.plist is the stable URL fallback for
/// Sparkle's own sanity check — this delegate always overrides it at
/// runtime.
final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {

    private static let stableFeedURL = "https://koala.eularix.com/appcast.xml"
    private static let betaFeedURL   = "https://koala.eularix.com/appcast-beta.xml"

    func feedURLString(for updater: SPUUpdater) -> String? {
        return FeatureFlags.betaChannel ? Self.betaFeedURL : Self.stableFeedURL
    }
}
