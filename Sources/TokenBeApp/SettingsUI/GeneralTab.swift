import SwiftUI
import TokenBeCore

/// General tab (08 § Settings, Paper `11D-0`). Every control writes its 09 key through `Settings`; what consumes
/// each value is in 09. The menu bar metric is stored now and drawn beside the glyph from 5.5 (14 § Stage 1.3).
struct GeneralTab: View {
  @Bindable var settings: TokenBeCore.Settings

  var body: some View {
    Form {
      Section {
        Toggle(Strings.launchAtLogin, isOn: $settings.generalLaunchAtLogin)
          .accessibilityIdentifier("settings.general.launchAtLogin")
      }
      Section {
        Picker(Strings.menuBarGlyph, selection: $settings.menubarGlyphStyle) {
          Text(Strings.glyphRing).tag("ring")
        }
        .accessibilityIdentifier("settings.general.glyphStyle")
        Picker(Strings.menuBarMetric, selection: $settings.menubarMetric) {
          Text(Strings.metricNone).tag("none")
          Text(Strings.metricMinRunway).tag("minRunway")
          Text(Strings.metricMinRemaining).tag("minRemaining")
          Text(Strings.metricTodaySpend).tag("todaySpend")
        }
        .accessibilityIdentifier("settings.general.menubarMetric")
      }
      Section {
        Picker(Strings.pinnedMetric, selection: $settings.popoverPinnedMetric) {
          Text(Strings.pinnedRunway).tag("runway")
          Text(Strings.pinnedRemaining).tag("remaining")
          Text(Strings.metricTodaySpend).tag("todaySpend")
        }
        .accessibilityIdentifier("settings.general.pinnedMetric")
        Picker(Strings.sort, selection: $settings.popoverSort) {
          Text(Strings.sortRunway).tag("runway")
          Text(Strings.sortRemaining).tag("remaining")
          Text(Strings.sortName).tag("name")
          Text(Strings.sortManual).tag("manual")
        }
        .accessibilityIdentifier("settings.general.sort")
      }
      Section {
        // 08: USD only in v1; the picker is shown disabled with its caption.
        Picker(Strings.currencyDisplay, selection: $settings.uiCurrencyDisplay) {
          Text(Strings.currencyNative).tag("native")
        }
        .disabled(true)
        .accessibilityIdentifier("settings.general.currencyDisplay")
        Text(Strings.currencyCaption)
          .font(.caption)
          .foregroundStyle(.secondary)
        Toggle(Strings.hideCents, isOn: $settings.uiHideCents)
          .accessibilityIdentifier("settings.general.hideCents")
      }
      Section {
        Picker(Strings.appearance, selection: $settings.uiAppearance) {
          Text(Strings.appearanceSystem).tag("system")
          Text(Strings.appearanceLight).tag("light")
          Text(Strings.appearanceDark).tag("dark")
        }
        .accessibilityIdentifier("settings.general.appearance")
        Toggle(Strings.useSystemAccent, isOn: $settings.uiUseSystemAccent)
          .accessibilityIdentifier("settings.general.useSystemAccent")
        LabeledContent(Strings.globalShortcut) {
          HotKeyRecorder(setting: $settings.uiShortcut)
        }
      }
    }
    .formStyle(.grouped)
  }
}
