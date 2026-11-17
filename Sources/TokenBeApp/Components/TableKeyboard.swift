import SwiftUI

/// 08 § Accessibility, "all tables keyboard navigable", for the Dashboard's grid tables (the runway board, By app,
/// By model; the ledger is a `List` and navigates on its own). Each row's first cell takes keyboard focus: Tab and
/// ⇧Tab reach it, ↑/↓ move between rows in order, Esc leaves the table. VoiceOver reads the focused row's cells
/// with their titles. The pattern is the popover's ↑/↓ between cards (08 § Popover 4).
struct TableRowFocus: ViewModifier {
  let id: String
  let focus: FocusState<String?>.Binding

  func body(content: Content) -> some View {
    content
      .focusable()
      .focused(focus, equals: id)
  }
}

struct TableKeyboard: ViewModifier {
  /// The rows' ids in display order.
  let ids: [String]
  let focus: FocusState<String?>.Binding

  func body(content: Content) -> some View {
    content
      .onKeyPress(.downArrow) { move(by: 1) }
      .onKeyPress(.upArrow) { move(by: -1) }
      // macOS delivers Esc as the exit command (`cancelOperation:`), not as a key press.
      .onExitCommand { focus.wrappedValue = nil }
  }

  /// Moves within the table only while a row has focus, so the keys keep their meaning elsewhere.
  private func move(by step: Int) -> KeyPress.Result {
    guard let current = focus.wrappedValue, let index = ids.firstIndex(of: current) else { return .ignored }
    focus.wrappedValue = ids[min(max(index + step, 0), ids.count - 1)]
    return .handled
  }
}

extension View {
  /// The row's focus target (its first cell, 08 § Accessibility).
  func tableRowFocus(_ id: String, _ focus: FocusState<String?>.Binding) -> some View {
    modifier(TableRowFocus(id: id, focus: focus))
  }

  /// ↑/↓ and Esc for a table whose rows use `tableRowFocus`.
  func tableKeyboard(_ ids: [String], _ focus: FocusState<String?>.Binding) -> some View {
    modifier(TableKeyboard(ids: ids, focus: focus))
  }
}
