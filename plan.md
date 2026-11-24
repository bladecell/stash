# Stash — plan

CopyQ-style clipboard manager as a DMS daemon plugin (id `stash`, no bar widget).
Remote: `git@github-personal:bladecell/stash.git`. Push after each working phase.

## Spec (settled 2026-11-24)

- **Storage**: DMS clipboard daemon captures history (`dms cl`, raise `maxHistory` to 2000). Own SQLite via
  `QtQuick.LocalStorage` (in-process) for edits/overlays, collections, pins, slots, encrypted items.
- **Tabs**: filter tabs over history (Clipboard, URLs, Images, Colors, Code, Emails, Paths) + collection tabs
  (Notes, Snippets, Pinned, Emoji, user tabs). Search = current tab, toggle for all.
- **Window**: ~560×480 centered on focused output, overlay layer, DMS theme tokens, FA Pro `regular` icons in tinted squares.
- **Keys**: Enter paste (terminal app_id → ctrl+shift+v), Ctrl+Enter copy only, Shift+Enter plain text,
  Alt+1..9 paste Nth visible, arrows/PgUp/PgDn/Home/End, Ctrl+Tab / Ctrl+←→ tabs, Ctrl+N new,
  F2/Ctrl+E inline edit, Del delete + Ctrl+Z undo, Ctrl+K action menu, Ctrl+T new tab, Ctrl+P pin,
  Ctrl+L lock, Ctrl+, settings, Esc clear search → close.
- **Editing**: inline; history edits stored as overlay keyed by DMS id+hash, "edited" mark;
  "Open in default editor" (xdg-open or configured cmd, temp file watched, synced back; encrypted → /run/user);
  "Save copy to…" collection.
- **Global shortcuts**: niri only. Stash exposes IPC (`toggle`, `pasteSlot N`, `lock`, …). Settings has an opt-in
  "Write default niri binds" button (Alt+V, Ctrl+Alt+1..9 into `dms/binds.kdl`, `niri validate`, rollback on fail).
  Slots default to history 1..9 (paste), each reassignable to a fixed item.
- **Encryption**: one master passphrase, `gpg --symmetric`, own prompt UI. Lock on idle timeout / screen lock /
  manual — each a plugin setting. Locked tab hides everything (no titles). Pasted secrets removed from DMS history; never shown in Clipboard tab.
- **Custom commands**: name, icon, shell cmd (stdin text or `$FILE`), output mode
  (replace/copy/paste/toast/discard), optional type/regex match, optional hotkey. JSON in plugin settings.
- **Code**: monospace + manual language tag; syntax highlight later (editor/preview only).
- **Migration**: import pins + notes from dux-copyq data; delete dux-copyq (ask first); ClipBoard+ stays disabled.

## Phases

- [x] 0. Five HTML mockups → picked **2 · Icon side rail**, plus rich rows: image thumbnails (~168×94),
      text up to 3 lines (code in mono), color rows with filled swatch + hex + rgb.
      Mockups: https://claude.ai/artifact/R4chgyCGHvgDaM7aymY1Nf
- [x] 1. Window, tabs, search, keyboard nav, paste on Enter, delete, history from DMS
- [~] 2. SQLite: new items, inline edit, external editor, notes/snippets/custom tabs, migration
      (built + store/editor self-tested; keyboard flows await user check; then remove dux-copyq)
- [ ] 3. Slots + IPC + niri-binds button
- [ ] 4. Custom commands
- [ ] 5. Encrypted tabs
- [ ] 6. Settings page + polish

## Open items

- Icons: FA Pro SVGs copied into repo (repo is private — keep it private).

## Dev notes

- `dms ipc call plugins reload stash` only re-reads `Stash.qml`; changes to other QML/JS files need `dms restart`.
- Window surface uses `Theme.popupTransparency` (floating-window transparency defaults to opaque); niri's
  all-windows blur rule shows through. DMS rule `dms-window-opaque` forces opacity 1.0 for `dev.duxlabs.shell`.
- DMS `clipboard.editEntry` replaces the entry: the edited text becomes a new newest entry with a new id.
- Collections DB: `~/.local/share/quickshell/QML/OfflineStorage/Databases/<md5>.sqlite` (Qt LocalStorage "stash").
- Keys: F2/^E edit, ^S save, Esc cancel, ^O external editor, ^N new item, ^T new tab, ^R rename tab,
  ^⇧Del delete tab (press twice), Tab/⇧Tab (± Ctrl) switch tabs. IPC: `openTab <label|id>`.
