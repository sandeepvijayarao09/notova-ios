import Foundation
import AuthenticationServices

/// Bridges `ASWebAuthenticationSession` into an `async` call that opens
/// `authorizeUrl` and resolves with the `notova://` callback URL. Maps user
/// cancellation onto `ASWebAuthError.canceled` so view models can treat it as a
/// non-error.
@MainActor
enum WebAuthSession {
    static let callbackScheme = "notova"

    /// Opens the OAuth authorize URL and returns the callback URL.
    static func authorize(url: URL) async throws -> URL {
        let presenter = PresentationContextProvider()
        return try await withCheckedThrowingContinuation { continuation in
            let webSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: ASWebAuthError.canceled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: ASWebAuthError.presentationFailed)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            webSession.presentationContextProvider = presenter
            webSession.prefersEphemeralWebBrowserSession = false
            // Keep the presenter alive for the lifetime of the session.
            objc_setAssociatedObject(webSession, &presenterKey, presenter, .OBJC_ASSOCIATION_RETAIN)
            if !webSession.start() {
                continuation.resume(throwing: ASWebAuthError.presentationFailed)
            }
        }
    }
}

private nonisolated(unsafe) var presenterKey: UInt8 = 0

/// Supplies the anchor window for the web auth sheet.
private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
