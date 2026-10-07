// Copyright 2026 Stefan Radermacher
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Observation
import StoreKit
import SwiftUI

/// Voluntary tips via the App Store. Tips unlock nothing; the app stays free.
@MainActor
@Observable
final class TipJar {
    static let shared = TipJar()

    /// The tips, cheapest first. Emoji and name belong to the app, so they follow its language;
    /// only the price comes from the App Store, which uses the language of the App Store account.
    enum Tip: String, CaseIterable {
        case coffee = "com.stefanradermacher.schreibmaschine.tip.coffee"
        case breakfast = "com.stefanradermacher.schreibmaschine.tip.breakfast"
        case dinner = "com.stefanradermacher.schreibmaschine.tip.dinner"

        var emoji: String {
            switch self {
            case .coffee: "☕️"
            case .breakfast: "🥐"
            case .dinner: "🍝"
            }
        }

        var name: String {
            switch self {
            case .coffee: String(localized: "Ein Kaffee")
            case .breakfast: String(localized: "Ein Frühstück")
            case .dinner: String(localized: "Ein Abendessen")
            }
        }

        var thanks: String {
            switch self {
            case .coffee: String(localized: "Danke für den Kaffee!")
            case .breakfast: String(localized: "Danke für das Frühstück!")
            case .dinner: String(localized: "Danke für das Abendessen!")
            }
        }
    }

    enum State: Equatable {
        case loading
        case ready
        /// No App Store products: in a build that does not come from the App Store, or because
        /// the App Store could not be reached.
        case unavailable
    }

    /// Whether this copy comes from the App Store or TestFlight. Only then can the tips load at
    /// all, so only then is it worth trying again.
    var isFromAppStore: Bool {
        Bundle.main.appStoreReceiptURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    private(set) var state = State.loading
    private(set) var products: [Tip: Product] = [:]
    private(set) var purchasing: Tip?
    /// Shown after a completed purchase, until the window closes.
    private(set) var thankedFor: Tip?
    private(set) var message: String?

    @ObservationIgnored private var updates: Task<Void, Never>?

    private init() {}

    /// Finishes purchases that complete outside the app's own flow, e.g. after an approval
    /// (Ask to Buy) or on another device. Call once at launch.
    func startListening() {
        guard updates == nil else { return }
        updates = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    if let tip = Tip(rawValue: transaction.productID) { self.thankedFor = tip }
                }
            }
        }
    }

    func loadProducts() async {
        guard state != .ready else { return }
        state = .loading
        do {
            let loaded = try await Product.products(for: Tip.allCases.map(\.rawValue))
            products = Dictionary(uniqueKeysWithValues: loaded.compactMap { product in
                Tip(rawValue: product.id).map { ($0, product) }
            })
            state = products.isEmpty ? .unavailable : .ready
        } catch {
            state = .unavailable
        }
    }

    func purchase(_ tip: Tip) async {
        guard let product = products[tip], purchasing == nil else { return }
        purchasing = tip
        message = nil
        defer { purchasing = nil }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                thankedFor = tip
            case .success(.unverified):
                message = String(localized: "Der Kauf konnte nicht bestätigt werden.")
            case .pending:
                message = String(localized: "Der Kauf wartet noch auf eine Bestätigung.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = String(localized: "Der Kauf ist nicht zustande gekommen.")
        }
    }

    func resetThanks() {
        thankedFor = nil
        message = nil
    }
}

/// The tip buttons, used in the About window and in the Support window.
struct TipJarView: View {
    private let jar = TipJar.shared

    var body: some View {
        VStack(spacing: 10) {
            if let tip = jar.thankedFor {
                VStack(spacing: 4) {
                    Text(tip.emoji).font(.system(size: 34))
                    Text(tip.thanks).font(.headline)
                    Text("Vielen Dank für deine Unterstützung!")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                Text("Die Schreibmaschine ist ein unabhängiges Open-Source-Projekt und bleibt vollständig kostenlos. Wenn du mir für die Weiterentwicklung etwas ausgeben möchtest, würde ich mich freuen:")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                switch jar.state {
                case .loading:
                    ProgressView().controlSize(.small).frame(height: 64)
                case .ready:
                    HStack(spacing: 10) {
                        ForEach(TipJar.Tip.allCases, id: \.self) { tip in
                            tipButton(tip)
                        }
                    }
                case .unavailable:
                    if jar.isFromAppStore {
                        // Usually a passing problem with the App Store; App Review once saw only
                        // a note here and could not find the purchases.
                        VStack(spacing: 8) {
                            Text("Die Preise konnten gerade nicht vom App Store geladen werden.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Erneut versuchen") {
                                Task { await jar.loadProducts() }
                            }
                            .controlSize(.small)
                        }
                        .frame(minHeight: 64)
                    } else {
                        Text("Ein Trinkgeld ist in der Version aus dem App Store möglich.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let message = jar.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.default, value: jar.thankedFor)
        .task { await jar.loadProducts() }
        .onDisappear { jar.resetThanks() }
    }

    @ViewBuilder
    private func tipButton(_ tip: TipJar.Tip) -> some View {
        let product = jar.products[tip]
        Button {
            Task { await jar.purchase(tip) }
        } label: {
            VStack(spacing: 3) {
                Text(tip.emoji).font(.system(size: 24))
                Text(tip.name)
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Group {
                    if jar.purchasing == tip {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text(product?.displayPrice ?? "")
                    }
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(height: 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .disabled(product == nil || jar.purchasing != nil)
        .help(tip.name)
    }
}

/// Window behind "Help → Support Schreibmaschine …": only the tip jar, without the rest of the About window.
struct SupportView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Schreibmaschine unterstützen")
                .font(.title2.weight(.semibold))
            TipJarView()
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
