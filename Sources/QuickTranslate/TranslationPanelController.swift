import AppKit
import SwiftUI

@MainActor
final class TranslationPanelController: NSObject {
    private let panel: NSPanel
    private let content = TranslationContentView()

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 170),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: TranslationCard(content: content))
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            if event.type == .leftMouseDown || event.keyCode == 53 {
                DispatchQueue.main.async { self?.dismiss() }
            }
        }
    }

    func show(source: String, translation: String, sourceLanguage: Language, targetLanguage: Language) {
        content.state = .result(
            source: source,
            translation: translation,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
        updateSize()
        if !panel.isVisible { presentNearMouse() }
    }

    func show(message: String) {
        content.state = .message(message)
        updateSize()
        presentNearMouse()
    }

    func showLoading() {
        content.state = .loading
        updateSize()
        presentNearMouse()
    }

    func dismiss() {
        panel.orderOut(nil)
    }

    private func presentNearMouse() {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let margin: CGFloat = 12
        let width = panel.frame.width
        let height = panel.frame.height
        let x = min(max(point.x + margin, screen.visibleFrame.minX + margin), screen.visibleFrame.maxX - width - margin)
        let below = point.y - height - margin
        let y = below >= screen.visibleFrame.minY ? below : min(point.y + margin, screen.visibleFrame.maxY - height - margin)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }

    private func updateSize() {
        panel.contentView?.layoutSubtreeIfNeeded()
        let fittingHeight = panel.contentView?.fittingSize.height ?? 170
        panel.setContentSize(NSSize(width: 380, height: min(max(fittingHeight, 170), 320)))
    }
}

@MainActor
private final class TranslationContentView: ObservableObject {
    @Published var state: TranslationCardState = .loading
}

private enum TranslationCardState {
    case loading
    case result(source: String, translation: String, sourceLanguage: Language, targetLanguage: Language)
    case message(String)
}

private struct TranslationCard: View {
    @ObservedObject var content: TranslationContentView

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            cardBody
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "quote.bubble.fill")
                .foregroundStyle(.tint)
            Text(metaTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if case .result = content.state {
                Text("本地")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        switch content.state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("翻译中…")
                    .font(.title3.weight(.semibold))
            }

        case let .message(message):
            Text(message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

        case let .result(source, translation, _, _):
            Text(translation)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(6)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("原文")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(source)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text("完全在本地翻译")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(translation, forType: .string)
                }
            }
        }
    }

    private var metaTitle: String {
        switch content.state {
        case .loading: "正在读取并翻译"
        case .message: "Qiu"
        case let .result(_, _, source, target): "\(languageLabel(source)) → \(languageLabel(target))"
        }
    }

    private func languageLabel(_ language: Language) -> String {
        switch language {
        case .english: "英"
        case .chinese: "中"
        }
    }
}
