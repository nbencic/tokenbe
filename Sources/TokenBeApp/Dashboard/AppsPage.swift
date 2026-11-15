import SwiftUI
import TokenBeCore

/// The sidebar's **Apps** page (08 § Dashboard window: "all apps flattened"; 14 § Stage 7.1): every app with its
/// editable display name, its immutable name (the harness tag, O-13) and the keys bound to it. The `unassigned`
/// sentinel (V4) is not listed: it is not an app the user made or can rename.
struct AppsPage: View {
  let model: AppModel

  private var apps: [AppRecord] { model.apps.filter { $0.id != Attribution.unassignedID } }

  var body: some View {
    Group {
      if apps.isEmpty {
        VStack(spacing: 6) {
          Text(Strings.noAppsYet)
            .font(.title3.weight(.semibold))
          Text(Strings.noAppsBody)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.apps.empty")
      } else {
        Form {
          ForEach(apps, id: \.id) { app in
            AppRowEditor(app: app, keys: keys(of: app)) { model.renameApp(app.id, to: $0) }
          }
        }
        .formStyle(.grouped)
      }
    }
    .navigationTitle(Strings.apps)
    .accessibilityIdentifier("dashboard.apps")
  }

  /// `OpenAI …a1b2` for each provider key bound to the app.
  private func keys(of app: AppRecord) -> [String] {
    model.bindings.filter { $0.appId == app.id && $0.kind == "provider_key" }.map { binding in
      let account = model.records.first { $0.id == binding.accountId }?.label ?? ""
      let key = model.providerKeys.first { $0.accountId == binding.accountId && $0.providerKeyId == binding.value }
      let hint = key?.redacted.flatMap { $0.count >= 4 ? Strings.hint(String($0.suffix(4))) : nil } ?? Strings.noApp
      return "\(account) \(hint)"
    }
  }
}

/// One app: the display name, committed on Return or when the field loses focus; the name below it.
private struct AppRowEditor: View {
  let app: AppRecord
  let keys: [String]
  let rename: (String) -> Void
  @State private var displayName = ""
  @FocusState private var focused: Bool

  var body: some View {
    Section {
      TextField(Strings.appNameField, text: $displayName)
        .focused($focused)
        .onSubmit(commit)
        .onChange(of: focused) { if !focused { commit() } }
        .accessibilityIdentifier("dashboard.apps.\(app.name).displayName")
      LabeledContent(Strings.appTag) {
        Text(app.name).monospaced().textSelection(.enabled)
      }
      if !keys.isEmpty {
        LabeledContent(Strings.columnKey) {
          Text(keys.joined(separator: ", ")).monospaced()
        }
      }
    }
    .onAppear { displayName = app.displayName }
    .onChange(of: app.displayName) { displayName = app.displayName }
  }

  private func commit() {
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      displayName = app.displayName
      return
    }
    if trimmed != app.displayName { rename(trimmed) }
  }
}
