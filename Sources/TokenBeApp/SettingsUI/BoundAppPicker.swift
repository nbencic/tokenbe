import SwiftUI
import TokenBeCore

/// Keys & apps `Bound app` (08 § Settings → Accounts; 14 § Stage 7.1): `—`, the apps (the `unassigned` sentinel is not
/// offered), then `New app…`, which asks for a name and binds the key to the new app (O-16).
struct BoundAppPicker: View {
  let model: AppModel
  let key: ProviderKeyRef
  /// The provider's key name, offered as the new app's name.
  let suggestion: String
  @Binding var naming: NamingTarget?

  private static let newAppTag = "\u{0}new"

  private var bound: String {
    model.bindings.first {
      $0.accountId == key.accountID && $0.kind == "provider_key" && $0.value == key.providerKeyID
    }?.appId ?? ""
  }

  var body: some View {
    // A closure, not the method reference `set: choose`: Swift 6.1 (CI's Xcode 16.4) crashed in IRGen on the
    // reabstraction thunk of a main-actor method passed as the setter (PM-7.1-7).
    Picker(Strings.boundApp, selection: Binding(get: { bound }, set: { choose($0) })) {
      Text(Strings.noApp).tag("")
      ForEach(model.apps.filter { $0.id != Attribution.unassignedID }, id: \.id) { app in
        Text(app.displayName).tag(app.id)
      }
      Divider()
      Text(Strings.newApp).tag(Self.newAppTag)
    }
    .labelsHidden()
    .fixedSize()
    .accessibilityIdentifier("settings.accounts.key.\(key.providerKeyID).app")
  }

  private func choose(_ choice: String) {
    if choice == Self.newAppTag {
      naming = NamingTarget(key: key, suggestion: suggestion)
    } else if choice != bound {
      model.bind(key, to: choice.isEmpty ? nil : choice)
    }
  }
}
