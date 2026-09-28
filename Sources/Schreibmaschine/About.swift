import AppKit
import SwiftUI

/// Addresses used in the About window and the Help menu, kept in one place. The source code
/// and its issue tracker join them once the repository is public.
enum AppLinks {
    static let moreProjects = URL(string: "https://stefanradermacher.com/projects")!
    static let productPage = URL(string: "https://stefanradermacher.com/projects/schreibmaschine")!
    static let help = URL(string: "https://stefanradermacher.com/projects/schreibmaschine/support")!
    static let privacy = URL(string: "https://stefanradermacher.com/projects/schreibmaschine/datenschutz")!
    static let feedback = URL(string: "mailto:schreibmaschine@stefanradermacher.com")!
}

/// A small window with SwiftUI content and no visible title bar, for "About" and "Support".
/// Each is made once and shown again; closing only hides it.
final class InfoWindowController: NSWindowController, NSWindowDelegate {
    static let about = InfoWindowController(title: String(localized: "Über Schreibmaschine"), content: AboutView())
    static let support = InfoWindowController(title: String(localized: "Schreibmaschine unterstützen"), content: SupportView())

    private init(title: String, content: some View) {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = title
        window.isMovableByWindowBackground = true
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        if window?.isVisible != true { window?.center() }
        super.showWindow(sender)
    }
}

struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    private var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 18) {
            header
            promises
            TipJarView()
            links
            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text(verbatim: "Schreibmaschine")
                .font(.system(size: 26, weight: .semibold))
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Ein Texteditor für Text und Code.\nKein IDE-Ersatz, sondern ein Werkzeug zum Schreiben.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if let nameNote {
                Text(nameNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Only for English readers: what the German app name means.
    private var nameNote: String? {
        guard Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true else { return nil }
        return "“Schreibmaschine” [ˈʃʁaɪ̯pmaˌʃiːnə] is the German word for “typewriter”."
    }

    /// What the app promises: free, open, without ads, without collecting data.
    private var promises: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    promise("Kostenlos", "gift")
                    promise("Open Source (Apache 2.0)", "chevron.left.forwardslash.chevron.right")
                }
                GridRow {
                    promise("Werbefrei", "rectangle.slash")
                    promise("Keine Datensammlung", "hand.raised")
                }
            }
            Text("Die Schreibmaschine hat kein Tracking, keine Analyse und keine Werbung und baut selbst keine Verbindungen ins Internet auf; nur ein freiwilliges Trinkgeld läuft über den App Store. Deine Texte und Einstellungen bleiben auf deinem Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func promise(_ title: LocalizedStringKey, _ symbol: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 18)
        }
        // Each column is only as wide as its longest entry, so nothing wraps.
        .fixedSize(horizontal: true, vertical: false)
    }

    private var links: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                monogram
                Link("Schreibmaschine im Web", destination: AppLinks.productPage)
                separator
                Link("Weitere Werkzeuge von mir", destination: AppLinks.moreProjects)
            }
            HStack(spacing: 6) {
                Link("Hilfe", destination: AppLinks.help)
                separator
                Link("Datenschutz", destination: AppLinks.privacy)
            }
        }
        .font(.callout)
        .fixedSize()
    }

    private var separator: some View {
        Text(verbatim: "·").foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var monogram: some View {
        let name = colorScheme == .dark ? "Monogram-Dark" : "Monogram"
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 18, height: 18)
                .opacity(0.8)
                .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            Text("\(copyright) · Apache-Lizenz 2.0")
            Text("Nur Apple-Frameworks, keine Fremdkomponenten.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
}
