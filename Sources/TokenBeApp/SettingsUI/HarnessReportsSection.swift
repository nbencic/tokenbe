import AppKit
import SwiftUI
import TokenBeCore

/// Settings → Sources → **Harness reports** (08 § Settings, Paper `21S-0`; 14 § Stage 7.2 step 6): the drop folder
/// (read-only, `Reveal in Finder`), the watch toggle (09 `tb.ingest.enabled`), move-when-done
/// (`tb.ingest.moveWhenDone`), the status line, today's counters, and `Copy reporter snippet` (Python/Node, the
/// files of `docs/reporters/` bundled with the app). Lines for providers with no account are counted (O-12).
struct HarnessReportsSection: View {
  @Bindable var settings: TokenBeCore.Settings
  let model: AppModel
  /// The folder the ingest service reads (the test root's in UI tests); nil before startup step 5.
  let folder: URL?
  @State private var copied: Snippet?

  enum Snippet: String, CaseIterable, Identifiable {
    case python = "py"
    case node = "js"

    var id: String { rawValue }
    var label: String { self == .python ? Strings.snippetPython : Strings.snippetNode }
  }

  var body: some View {
    Section(Strings.harnessReports) {
      LabeledContent(Strings.harnessFolder) {
        HStack(spacing: 8) {
          Text(folder?.path ?? settings.ingestFolderPath)
            .font(.caption.monospaced())
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .accessibilityIdentifier("settings.sources.harness.folder")
          Button(Strings.revealInFinder) { reveal() }
            .disabled(folder == nil)
            .accessibilityIdentifier("settings.sources.harness.reveal")
        }
      }
      Toggle(Strings.harnessWatch, isOn: $settings.ingestEnabled)
        .accessibilityIdentifier("settings.sources.harness.watch")
      Toggle(Strings.harnessMoveWhenDone, isOn: $settings.ingestMoveWhenDone)
        .accessibilityIdentifier("settings.sources.harness.moveWhenDone")
      TimelineView(.periodic(from: .now, by: 1)) { context in
        Text(statusLine(now: context.date))
          .foregroundStyle(model.ingestStatus.mode == .unwritable ? Color(.healthLow) : Color.secondary)
          .accessibilityIdentifier("settings.sources.harness.status")
      }
      Text(Strings.harnessToday(inserted: model.ingestStatus.linesOK, duplicate: model.ingestStatus.linesDuplicate,
                                rejected: model.ingestStatus.linesRejected))
        .font(.callout.monospacedDigit())
        .accessibilityIdentifier("settings.sources.harness.counters")
      if model.harnessWithoutAccount > 0 {
        Text(Strings.harnessWithoutAccount(model.harnessWithoutAccount))
          .font(.callout)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("settings.sources.harness.withoutAccount")
      }
      ForEach(model.ingestStatus.largeFiles, id: \.self) { name in
        Text(Strings.harnessRotate(name))
          .font(.callout)
          .foregroundStyle(Color(.healthWatch))
      }
      HStack {
        Menu(Strings.copyReporterSnippet) {
          ForEach(Snippet.allCases) { snippet in
            Button(snippet.label) { copy(snippet) }
          }
        }
        .fixedSize()
        .accessibilityIdentifier("settings.sources.harness.copySnippet")
        if let copied {
          Text(Strings.snippetCopied(copied.label))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  /// `Watching · 2 files · last line 14 s ago` (08); `Off` while the watch is off; red when the folder is not writable.
  private func statusLine(now: Date) -> String {
    let status = model.ingestStatus
    switch status.mode {
    case .unwritable: return Strings.harnessUnwritable
    case .stopped: return Strings.harnessOff
    case .fsevents, .poll:
      let last = status.lastLineAt.map { date -> String in
        let seconds = Int(now.timeIntervalSince(date))
        return seconds < 60 ? Strings.secondsAgo(max(0, seconds))
          : Formatters.freshness(date, now: now, calendar: .current)
      }
      return Strings.harnessWatching(files: status.files, lastLine: last)
    }
  }

  private func reveal() {
    guard let folder else { return }
    NSWorkspace.shared.activateFileViewerSelecting([folder])
  }

  /// Copies the bundled reporter (`Resources/reporters/tokenbe_report.<ext>`, `docs/reporters/` verbatim).
  private func copy(_ snippet: Snippet) {
    do {
      guard let url = Bundle.main.url(forResource: "tokenbe_report", withExtension: snippet.rawValue) else {
        throw CocoaError(.fileNoSuchFile)
      }
      let text = try String(contentsOf: url, encoding: .utf8)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      copied = snippet
    } catch {
      Log.error(.uiError, cat: .ui, msg: "reporter snippet not copied", err: error, ctx: ["view": "settings.sources"])
    }
  }
}
