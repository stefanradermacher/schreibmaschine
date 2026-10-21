import AppKit
import WebKit

/// The Markdown preview beside the text: the HTML of MarkdownRenderer in a web view that loads
/// nothing from the network and runs no code from the document. Links open in the browser.
///
/// The page is loaded once; afterwards only its content is replaced, so it keeps its scroll
/// position and does not flicker while typing. It follows the text by its headings: the part
/// between two headings in the text is shown as the same share between them in the preview.
final class MarkdownPreview: NSView, WKNavigationDelegate {
    private let webView: WKWebView
    private var isLoaded = false
    private var pendingHTML: String?
    private var pendingScroll: String?

    init(baseURL: URL?) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        webView.loadHTMLString(Self.page, baseURL: baseURL)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(html: String) {
        guard isLoaded else { pendingHTML = html; return }
        webView.evaluateJavaScript("document.getElementById('content').innerHTML = \(Self.literal(html));") { _, error in
            #if DEBUG
            if let error { NSLog("PREVIEW Fehler beim Einsetzen: %@", String(describing: error)) }
            #endif
        }
    }

    /// Scrolls to the place between heading `index` and the next one (0: before the first),
    /// `fraction` of the way.
    func scroll(betweenHeading index: Int, fraction: Double) {
        let script = """
        (function() {
          var a = \(index) == 0 ? 0 : (document.getElementById('h\(index)') || {offsetTop: 0}).offsetTop;
          var next = document.getElementById('h\(index + 1)');
          var b = next ? next.offsetTop : document.documentElement.scrollHeight - window.innerHeight;
          window.scrollTo(0, Math.max(0, a + (b - a) * \(fraction.isFinite ? fraction : 0) - 12));
        })();
        """
        guard isLoaded else { pendingScroll = script; return }
        webView.evaluateJavaScript(script)
    }

    /// A string as a JavaScript literal.
    private static func literal(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let json = String(data: data, encoding: .utf8)
        else { return "''" }
        return String(json.dropFirst().dropLast())
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        NSLog("PREVIEW geladen")
        #endif
        isLoaded = true
        if let html = pendingHTML { pendingHTML = nil; show(html: html) }
        if let script = pendingScroll { pendingScroll = nil; webView.evaluateJavaScript(script) }
    }

    /// Only the page itself is loaded here; links go to the browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated, let url = action.request.url {
            if url.fragment != nil, url.scheme == "about" || url.isFileURL {
                return decisionHandler(.allow)
            }
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(action.navigationType == .other ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        #if DEBUG
        NSLog("PREVIEW Laden fehlgeschlagen: %@", String(describing: error))
        #endif
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        #if DEBUG
        NSLog("PREVIEW Laden fehlgeschlagen (vorläufig): %@", String(describing: error))
        #endif
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        #if DEBUG
        NSLog("PREVIEW Webprozess beendet")
        #endif
    }

    // MARK: - Page

    /// Nothing from the network, no scripts from the document: the content security policy
    /// allows only the styles below and images next to the file.
    private static let page = """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src file: data:">
    <style>
    :root { color-scheme: light dark; --text: #1d1d1f; --quiet: #6e6e73; --line: #d2d2d7; --code: #f2f2f5; --accent: #3f6fb4; }
    @media (prefers-color-scheme: dark) { :root { --text: #e8e8ed; --quiet: #98989d; --line: #3a3a3c; --code: #2c2c2e; --accent: #6e9cdc; } }
    html { font: 15px/1.6 -apple-system, "SF Pro Text", sans-serif; color: var(--text); background: transparent; }
    body { max-width: 46em; margin: 0 auto; padding: 18px 28px 40vh; -webkit-font-smoothing: antialiased; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.4em 0 0.5em; }
    h1 { font-size: 1.9em; } h2 { font-size: 1.45em; border-bottom: 1px solid var(--line); padding-bottom: 0.2em; }
    h3 { font-size: 1.2em; } h4, h5, h6 { font-size: 1em; }
    p, ul, ol, blockquote, pre, table { margin: 0 0 0.9em; }
    a { color: var(--accent); text-decoration: none; } a:hover { text-decoration: underline; }
    code { font: 0.88em ui-monospace, "SF Mono", Menlo, monospace; background: var(--code); border-radius: 4px; padding: 0.1em 0.3em; }
    pre { background: var(--code); border-radius: 6px; padding: 0.8em 1em; overflow-x: auto; }
    pre code { background: none; padding: 0; font-size: 0.85em; }
    blockquote { margin-left: 0; padding-left: 1em; border-left: 3px solid var(--line); color: var(--quiet); }
    li > p { margin: 0; } li.task { list-style: none; } li.task input { margin: 0 0.4em 0 -1.4em; }
    table { border-collapse: collapse; } th, td { border: 1px solid var(--line); padding: 0.3em 0.7em; } th { background: var(--code); }
    hr { border: 0; border-top: 1px solid var(--line); margin: 1.5em 0; }
    img { max-width: 100%; }
    .missing-image { display: inline-block; border: 1px dashed var(--line); border-radius: 4px; padding: 0.2em 0.6em; color: var(--quiet); font-size: 0.9em; }
    .missing-image::before { content: "▧ "; }
    </style></head>
    <body><div id="content"></div></body></html>
    """
}
