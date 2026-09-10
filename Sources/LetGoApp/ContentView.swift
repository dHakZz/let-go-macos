import AppKit
#if canImport(LetGoCore)
import LetGoCore
#endif
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    let onShowSuggestions: () -> Void
    @State private var processToQuit: HoldingProcess?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if model.result != nil {
                resultActions
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $model.isWhatsNewPresented) {
            WhatsNewView(model: model)
        }
        .confirmationDialog(
            "Ask \(processToQuit.map(model.displayName(for:)) ?? "this process") to quit?",
            isPresented: Binding(
                get: { processToQuit != nil },
                set: { if !$0 { processToQuit = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Quit and Check Again") {
                if let processToQuit {
                    model.requestQuit(processToQuit)
                }
                processToQuit = nil
            }
            Button("Cancel", role: .cancel) {
                processToQuit = nil
            }
        } message: {
            Text("Unsaved changes in that app may be lost. Let Go sends a normal quit request and never force-quits system processes.")
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard
                    let data,
                    let text = String(data: data, encoding: .utf8),
                    let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
                else { return }
                Task { @MainActor in
                    model.inspect(url)
                }
            }
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                model.returnToStart()
            } label: {
                Image(nsImage: model.appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .shadow(color: .indigo.opacity(0.25), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .help("Return to the start screen")
            .accessibilityLabel("Return to Start")

            VStack(alignment: .leading, spacing: 2) {
                Text("Let Go")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("See what is holding a file, folder, or drive open.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onShowSuggestions()
            } label: {
                Label("Suggestions", systemImage: "lightbulb")
            }
            .buttonStyle(.link)
            .controlSize(.large)
            .help("Share an idea or improvement")
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .ready:
            emptyState
        case .scanning:
            scanningState
        case .loaded:
            if let result = model.result {
                resultState(result)
            }
        case .failed:
            errorState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Button {
                model.chooseTarget()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.055))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(
                                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.28),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                                )
                        }
                    VStack(spacing: 13) {
                        Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "doc.badge.magnifyingglass")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                        Text(isDropTargeted ? "Drop to inspect" : "Drop something here")
                            .font(.title3.weight(.semibold))
                        Text("Or click to choose a file, folder, or mounted drive")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Choose a file, folder, or mounted drive")
            .accessibilityLabel("Choose a file, folder, or mounted drive")
            .frame(maxWidth: 510, maxHeight: 250)
            Text("Nothing is uploaded. Let Go only checks your Mac when you ask it to.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(28)
    }

    private var scanningState: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Checking open files…")
                .font(.title3.weight(.semibold))
            Text("Large folders and drives can take a little longer.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func resultState(_ result: InspectionResult) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                targetSummary(result)

                if result.processes.isEmpty {
                    clearState(result)
                } else {
                    ForEach(result.processes) { process in
                        processCard(process)
                    }
                }

                if !result.processes.isEmpty {
                    automationActions(result)
                }
            }
            .padding(24)
        }
    }

    private func targetSummary(_ result: InspectionResult) -> some View {
        HStack(spacing: 14) {
            Image(nsImage: model.icon(for: result.target))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.target.lastPathComponent.isEmpty ? result.target.path : result.target.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text(result.target.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(result.kind.rawValue.capitalized)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func clearState(_ result: InspectionResult) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.green)
            Text("Nothing appears to be holding it open")
                .font(.title3.weight(.semibold))
            Text("You can try the operation again now.")
                .foregroundStyle(.secondary)

            if model.canEject(result) {
                Button {
                    model.ejectVolume()
                } label: {
                    Label("Eject Safely", systemImage: "eject.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(Color.green.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func processCard(_ process: HoldingProcess) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Image(nsImage: model.icon(for: process))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName(for: process))
                        .font(.headline)
                    Text(processSubtitle(process))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isSafeToQuit(process) {
                    Button("Quit…") {
                        processToQuit = process
                    }
                    .buttonStyle(.bordered)
                } else {
                    Label("System", systemImage: "lock.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            ForEach(Array(process.handles.prefix(4).enumerated()), id: \.offset) { _, handle in
                Button {
                    model.reveal(handle)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: accessIcon(handle.access))
                            .foregroundStyle(accessColor(handle.access))
                            .frame(width: 16)
                        Text(handle.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .help("Reveal this open item in Finder")
            }

            if process.handles.count > 4 {
                Text("and \(process.handles.count - 4) more open items")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func automationActions(_ result: InspectionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Automation", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Label("Included", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }

            Text("Let Go can keep checking in the background while you continue working.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    model.startWatching(autoEject: false)
                } label: {
                    Label(
                        model.watchPurpose == .notify ? "Watching…" : "Watch Until Free",
                        systemImage: "bell.fill"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(model.isWatching)

                if model.canEject(result) {
                    Button {
                        model.startWatching(autoEject: true)
                    } label: {
                        Label(
                            model.watchPurpose == .eject ? "Waiting to Eject…" : "Auto-Eject When Ready",
                            systemImage: "eject.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isWatching)
                }

                if model.isWatching {
                    Button("Stop") {
                        model.stopWatching()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.indigo.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var errorState: some View {
        VStack(spacing: 15) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            Text("That item could not be checked")
                .font(.title3.weight(.semibold))
            Text(model.errorMessage ?? "An unknown error occurred.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Choose Something Else") {
                model.chooseTarget()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private var resultActions: some View {
        HStack(spacing: 12) {
            if let actionMessage = model.actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Updated just now")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                model.revealTarget()
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.borderless)

            Button {
                model.rescan()
            } label: {
                Label("Check Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(model.status == .scanning)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Copyright © 2026 Justin Chacon. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            if model.supportURL != nil {
                Button("Support Let Go") {
                    model.openSupportPage()
                }
                .font(.caption)
                .buttonStyle(.link)

                Text("|")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button("Privacy & Safety") {
                model.showPrivacyInfo()
            }
            .font(.caption)
            .buttonStyle(.link)

            Text("|")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button(model.displayVersion) {
                model.showWhatsNew()
            }
                .font(.caption)
                .buttonStyle(.link)
                .help("See what’s new in this version")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func processSubtitle(_ process: HoldingProcess) -> String {
        let itemWord = process.handles.count == 1 ? "item" : "items"
        return "PID \(process.pid) · \(process.handles.count) open \(itemWord)"
    }

    private func accessIcon(_ access: String?) -> String {
        switch access {
        case "w", "u": return "pencil.circle.fill"
        case "r": return "eye.circle.fill"
        default: return "circle.fill"
        }
    }

    private func accessColor(_ access: String?) -> Color {
        switch access {
        case "w", "u": return .orange
        case "r": return .blue
        default: return .secondary
        }
    }
}

private struct WhatsNewView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: model.appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("What’s New!")
                        .font(.title2.bold())
                    Text(model.displayVersion)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            VStack(spacing: 0) {
                whatsNewRow(
                    icon: "hand.tap.fill",
                    text: "Click the drop area to choose a file, folder, or mounted drive."
                )
                Divider()
                whatsNewRow(
                    icon: "house.fill",
                    text: "Click the Let Go app icon to clear the current result and return to the start screen."
                )
                Divider()
                whatsNewRow(
                    icon: "sparkles",
                    text: "Watch Until Free and Auto-Eject When Ready are now included for everyone."
                )
                Divider()
                whatsNewRow(
                    icon: "arrow.clockwise",
                    text: "Reveal and Check Again stay together above the footer."
                )
            }
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 470)
    }

    private func whatsNewRow(icon: String, text: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.indigo)
                .frame(width: 28)

            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }
}
