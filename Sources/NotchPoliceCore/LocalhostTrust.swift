import Foundation

/// Antigravity's local language server uses a self-signed TLS certificate.
/// Trust is relaxed only for loopback hosts in this dedicated URLSession;
/// normal provider traffic continues to use the system trust store.
final class LocalhostTrust: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let host = challenge.protectionSpace.host
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              host == "127.0.0.1" || host == "localhost" || host == "::1",
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
