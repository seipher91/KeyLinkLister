# Changelog

## 1.0.1 (2026-09-12)

### Changed
- Default playstyle is now **Competitive** (3); 1.0.0 defaulted to 4, which the game labels "Carry Offered". A saved value of 4 is migrated once; change it any time with the playstyle button or `/kll playstyle <1-4>`.

### Fixed
- Keystone you don't own with the key holder in your party: the direct API listing is always refused by the server (the auto-generated title is empty without your own key, and `GetKeystoneForActivity` ignores party members), so the button now opens the pre-filled Blizzard panel in that case too. Type the suggested title and press Enter.

## 1.0.0 (2026-09-12)

First public release (retail Midnight 12.1).

### Added
- Click a Mythic Keystone link in chat: a **List Group** button appears under the tooltip and lists a Premade Group for that dungeon (playstyle picked with the button next to it).
- Keystone you don't own, alone: the button opens Blizzard's "Start a Group" panel with the dungeon and playstyle pre-selected and the cursor in the Title field; the suggested title (`+<level>`) is shown as placeholder — type it and press **Enter** (Enter lists the group). Blizzard blocks addons from writing that field.
- In a party without owning the key: direct listing is tried first (a member may hold the key); the next click opens the panel if the server refuses.
- Re-list for another dungeon in two clicks (remove, then create), same rules as the Blizzard Group Finder for leader / full group / instance group / authenticator.
- `/kll` (also `/keylinklister`, `/kl`): playstyle, cross-faction, private, required rating, title format, open-finder toggle, self-check (`test`), diagnostic log (`log`, `diag`, `debug`).
- English and Italian.
