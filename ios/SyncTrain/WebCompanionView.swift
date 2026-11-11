import SwiftUI
import WebKit

struct WebCompanionView: UIViewRepresentable {
    let urlString: String
    let reloadToken: UUID
    @Binding var isUsingOfflineFallback: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isUsingOfflineFallback: $isUsingOfflineFallback)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 9 / 255, green: 14 / 255, blue: 24 / 255, alpha: 1)
        loadTarget(in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let targetKey = "\(urlString)|\(reloadToken.uuidString)"
        if context.coordinator.lastTargetKey != targetKey {
            loadTarget(in: uiView, coordinator: context.coordinator)
        }
    }

    private func loadTarget(in webView: WKWebView, coordinator: Coordinator) {
        coordinator.lastTargetKey = "\(urlString)|\(reloadToken.uuidString)"
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https") {
            DispatchQueue.main.async {
                self.isUsingOfflineFallback = false
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 4.0
            webView.load(request)
        } else {
            loadOfflineFallback(in: webView)
        }
    }

    fileprivate func loadOfflineFallback(in webView: WKWebView) {
        DispatchQueue.main.async {
            self.isUsingOfflineFallback = true
        }
        if let htmlURL = Bundle.main.url(forResource: "offline_companion", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastTargetKey: String = ""
        @Binding var isUsingOfflineFallback: Bool

        init(isUsingOfflineFallback: Binding<Bool>) {
            _isUsingOfflineFallback = isUsingOfflineFallback
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fallbackIfNeeded(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fallbackIfNeeded(webView)
        }

        private func fallbackIfNeeded(_ webView: WKWebView) {
            DispatchQueue.main.async {
                self.isUsingOfflineFallback = true
            }
            if let htmlURL = Bundle.main.url(forResource: "offline_companion", withExtension: "html") {
                webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
            }
        }
    }
}
