import siwin/platforms/any/window
when defined(macosx):
  import siwin/platforms/cocoa/modifierstate

type ModifierState* = tuple[ctrlDown, shiftDown, altDown, cmdDown: bool]

proc modifierStateFromModifiers*(modifiers: set[ModifierKey]): ModifierState =
  (
    ctrlDown: ModifierKey.control in modifiers,
    shiftDown: ModifierKey.shift in modifiers,
    altDown: ModifierKey.alt in modifiers,
    cmdDown: ModifierKey.system in modifiers,
  )

proc modifierStateFromKeyboard*(keyboard: Keyboard): ModifierState =
  modifierStateFromModifiers(keyboard.modifiers)

proc modifierStateFromKeyEvent*(e: KeyEvent): ModifierState =
  modifierStateFromModifiers(e.modifiers)

when defined(macosx):
  proc tryModifierStateFromCgEvent(state: var ModifierState): bool =
    var modifiers: set[ModifierKey]
    if not tryCurrentModifierState(modifiers):
      return false
    state = modifierStateFromModifiers(modifiers)
    true

proc currentModifierState*(window: Window): ModifierState =
  result = modifierStateFromKeyboard(window.keyboard)
  when defined(macosx):
    discard tryModifierStateFromCgEvent(result)
