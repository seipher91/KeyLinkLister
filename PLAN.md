# KeyLinkLister — Piano e fattibilità

Addon retail **Midnight 12.1** (Interface 120100). Quando un amico linka una Mythic Keystone in chat e la clicchi, sotto il tooltip (`ItemRefTooltip`) compare un pulsante che crea il gruppo Premade per quel dungeon, oppure apre il pannello "Start a Group" già prefillato.

> Fonti verificate: sorgente Blizzard 12.1 `Blizzard_GroupFinder/Mainline/LFGList.lua`, `Blizzard_UIPanels_Game/Mainline/ItemRef.lua`, `LFGListInfoDocumentation.lua`, `LFGConstantsDocumentation.lua`, `ChallengeModeInfoDocumentation.lua` (repo Gethe/wow-ui-source, branch live) + addon installati (RaiderIO, idTip, PGFinder).

## 1. Verdetto: FATTIBILE

| Requisito | Come | Evidenza |
|---|---|---|
| Intercettare il click sul link keystone | `hooksecurefunc(ItemRefTooltip, "SetHyperlink")` (post-hook, come idTip). Link = `keystone:itemID:challengeMapID:level:affix×4` | `ItemRef.lua`: `SetItemRef` → `ItemRefTooltip:ItemRefSetHyperlink(link)` → `SetHyperlink`; stesso link = toggle/Hide |
| Pulsante nel tooltip | Frame figlio ancorato sotto il tooltip (`TooltipBackdropTemplate`), niente padding sul tooltip Blizzard | pattern standard, nessun taint |
| keystone → activity Group Finder | `C_ChallengeMode.GetMapUIInfo(challengeMapID)` → nome + `mapID` istanza; scan `GetAvailableActivityGroups/GetAvailableActivities(2, …, PvE)` e match `info.isMythicPlusActivity and info.mapID == mapID`, fallback per nome | doc 12.1: `GroupFinderActivityInfo.mapID`, `GetMapUIInfo` 6° return `mapID` |
| Creare il gruppo | `C_LFGList.SetEntryTitle(activityID, groupID, nil, generalPlaystyle)` poi `C_LFGList.CreateListing({activityIDs={id}, generalPlaystyle=…, …})` | `LFGListEntryCreation_ListGroupInternal` (12.1). Entrambe **HasRestrictions** + hardware event (dalla 7.2): OK dentro OnClick — stessa classe di `ApplyToGroup`, usata da PGF "one-click sign up" |
| Verifica leader / possibile | `UnitIsGroupLeader("player", HOME)`, non in gruppo istanza, gruppo non pieno, playstyle ≠ None, **senza authenticator serve possedere la key** (`IsPlayerAuthenticatedForLFG(2) or GetKeystoneForActivity(id)`) | `LFGListEntryCreation_UpdateValidState` |
| Aprire la schermata dello screenshot | fallback: `PVEFrame_ShowFrame` + `LFGListEntryCreation_Show/Select` prefillati (da click) | `LFGListCategorySelectionStartGroupButton_OnClick` |

### Stato dopo la review avversariale (12-09-2026)

- Path diretto (key propria) **verificato in-game dall'utente**: funziona.
- Key di un amico (utente solo): log mostra `CreateListing → true` (client ok) poi `LFG_LIST_ENTRY_CREATION_FAILED` senza messaggio: **il server rifiuta** il listing M+ senza una key di quel dungeon nel gruppo. Regola implementata: `GetKeystoneForActivity(id)` nil → il pulsante apre il pannello Blizzard prefillato ("Open panel"), dove con authenticator si digita il titolo e si preme List Group.
- Pannello da addon: `LFGListEntryCreation_Show` fa due `Select` → due `SetEntryTitle` nello stesso click → "Interface action failed because of an AddOn" (osservato). Ora: `Clear` + playstyle + **un solo** `Select` + `SetActivePanel`.
- Log persistente (`KeyLinkListerDB.log`, `/kl log|diag|debug`) con `UI_ERROR_MESSAGE`/`CHAT_MSG_SYSTEM` nei 15 s dopo il click; `/kl test <challengeMapID> <lvl>` simula il link di una key (Murder Row = 587).
- `RemoveListing` è anch'essa hardware-event → il re-list è in due click (rimuovi, poi crea). Nessun fallback nello stesso click: dopo un fallimento il pulsante diventa "Open panel".
- Pannello fallback: forzata la finestra PvE (`PVEFrame_ShowFrame("GroupFinderFrame","LFGListPVEStub")` + filtri PvE) — con l'ultima finestra usata PvP `LFGListUtil_OpenBestWindow` avrebbe fatto assert dentro `LFGListUtil_AugmentWithBest`.
- Risoluzione activity: prima con filtro `CurrentSeason` (evita doppioni di stagioni passate), poi PvE generico.

### Rischi (da verificare in-game con `/kl test`)

1. **"HasRestrictions" su `CreateListing`**: assunto = solo hardware event (come `ApplyToGroup`). Se il server/cliente bloccasse la chiamata da addon, il click cade automaticamente sul fallback "apri pannello prefillato" e stampa il motivo.
2. **`activityInfo.mapID`** potrebbe essere 0 per le activity M+: copre il fallback per nome (`shortName == nome dungeon`). `/kl test` confronta la mia risoluzione con `C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()` per la key posseduta.
3. **Titolo**: per M+ è generato dal server via `SetEntryTitle`; `CreateListing` ritorna `false` senza titolo valido → gestito (fallback pannello).
4. **Taint del pannello** (solo modalità/fallback `panel`): si chiamano funzioni Blizzard da addon; le API di listing sono hardware-event, non secure-only, quindi il click utente su "List Group" resta valido. Da provare con `/console taintLog 1`.
5. **Playstyle obbligatorio** (`GROUP_FINDER_PLAYSTYLE_REQUIRED`): default Expert (4, "Competitive"), ciclabile dal pulsante di destra o `/kl playstyle 1-4`.

## 2. Architettura

```
KeyLinkLister/
├── KeyLinkLister.toc          # Interface 120100, SavedVariables KeyLinkListerDB
├── KeyLinkLister.lua          # single-file (~450 righe)
└── tools/test_keylinklister.py  # test lupa con stub WoW (python tools/test_keylinklister.py)
```

Moduli logici nello stesso file: L10n (en/it) · DB · Parse/Resolve · CanList · DoListing/OpenCreationPanel · riga tooltip · slash · eventi · namespace `KeyLinkLister` per `/dump` e test.

## 3. Fasi

- [x] **F0 Ricerca API 12.1** — firme reali, hardware event, vincolo authenticator, formato link.
- [x] **F1 Core** — parse, resolve, CanList, createData, hook tooltip, listing + fallback, slash, eventi.
- [x] **F2 Test offline** — lupa: parse, resolve (mapID/nome), regole, createData, hook toggle, click→evento→open, slash.
- [ ] **F3 In-game** — `/kl test` (match Blizzard), click su key linkata da un amico con e senza authenticator, BugSack pulito, `taintLog` sul fallback.
- [ ] **F4 Rifiniture** — opzione "solo se sono leader" già implicita; eventuale bottone anche su `GameTooltip` (key in borsa); pubblicazione CurseForge.
