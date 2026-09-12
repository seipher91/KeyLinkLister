-- KeyLinkLister: clicca una Mythic Keystone linkata in chat e, sotto il tooltip, compare un
-- pulsante che crea (o ri-crea) il gruppo Premade per quel dungeon.
-- Retail Midnight 12.1+. Nessun secure template, nessun combat lockdown.
-- C_LFGList.CreateListing / SetEntryTitle richiedono un hardware event (dalla 7.2):
-- vengono chiamate SOLO dentro l'OnClick del pulsante (o da slash command).

local ADDON_NAME = ...
local VERSION = "1.0.0"

local DUNGEON_CATEGORY = GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2
local FILTER_PVE = (Enum and Enum.LFGListFilter and Enum.LFGListFilter.PvE) or 4
local FILTER_SEASON = (Enum and Enum.LFGListFilter and Enum.LFGListFilter.CurrentSeason) or 64
local LEGACY_PS_NONE = (Enum and Enum.LFGEntryPlaystyle and Enum.LFGEntryPlaystyle.None) or 0
local PS_NONE = 0
local PS_MAX = (Enum and Enum.LFGEntryGeneralPlaystyle and Enum.LFGEntryGeneralPlaystyle.Expert) or 4
local CAT_HOME = LE_PARTY_CATEGORY_HOME or 1
local CAT_INSTANCE = LE_PARTY_CATEGORY_INSTANCE or 2
local OPEN_WINDOW = 15 -- secondi: LFG_LIST_ACTIVE_ENTRY_UPDATE entro questa finestra è "nostro"

-- ---------------------------------------------------------------------------
-- Localizzazione: default enUS, override itIT
-- ---------------------------------------------------------------------------

local L = {
    LOADED = "v%s loaded — /keylinklister",
    LIST = LIST_GROUP or "List Group",
    RELIST = "Re-list Group",
    LISTED_SAME = "Already listed",
    OPEN_PANEL = "Open panel",
    BTN_TT_PS = "Playstyle: %s",
    NO_KEY_HINT = "No keystone for this dungeon in your group: the button opens the Blizzard panel pre-filled, type the title there and press List Group.",
    ERR_NOT_LEADER = "You are not the group leader.",
    ERR_INSTANCE_GROUP = "You are in an instance group.",
    ERR_FULL = "Your group is already full.",
    ERR_AUTH = "No authenticator on this account: you can only list dungeons whose keystone you own.",
    ERR_PLAYSTYLE = "Pick a playstyle first (button on the right).",
    ERR_NO_ACTIVITY = "No Group Finder activity found for this dungeon.",
    ERR_COMBAT = "Cannot open the Group Finder in combat.",
    LISTING = "Listing %s +%d…",
    LISTED = "Group listed. Applicants will show up in the Group Finder.",
    LIST_FAILED = "Direct listing failed (%s): click the button again to open the Group Finder panel.",
    CLIENT_REFUSED = "request refused by the client",
    CREATE_FAILED = "The server refused the listing.",
    RELIST_WAIT = "Listing removed: click the button again to create the new one.",
    PANEL_ERR = "Could not pre-fill the Group Finder panel (%s).",
    TYPE_TITLE = "Suggested title: |cffffffff%s|r — type it in the Title field (cursor is already there) and press List Group.",
    TITLE_FMT = "Title format: %s  (%%d = keystone level, %%s = playstyle)",
    DELISTED = "Listing removed.",
    NOT_LISTED = "No active listing.",
    PS_NONE = "(playstyle)",
    PS_TT = "Playstyle for the listing (click to cycle)",
    XF_ON = "Cross-faction listing: ON",
    XF_OFF = "Cross-faction listing: OFF",
    PRIV_ON = "Private group: ON",
    PRIV_OFF = "Private group: OFF",
    OPEN_ON = "Open Group Finder after listing: ON",
    OPEN_OFF = "Open Group Finder after listing: OFF",
    MODE = "Mode: %s (direct = list from the button, panel = open the create-group panel)",
    SCORE = "Required M+ rating: %d",
    PS_SET = "Playstyle: %s",
    TEST_NOKEY = "You own no keystone: test with /keylinklister test <challengeMapID> <level>.",
    TEST_HDR = "self-check",
    HELP = {
        "/keylinklister — this help",
        "/keylinklister playstyle [1-4] — show or set the listing playstyle",
        "/keylinklister xfaction | private | open — toggle options",
        "/keylinklister mode direct|panel — list directly or open the Blizzard panel",
        "/keylinklister score <n> — required M+ rating for applicants",
        "/keylinklister title <format> — suggested title for keys you don't own (default +%d; %s = playstyle)",
        "/keylinklister delist — remove your active listing",
        "/keylinklister status — print current state",
        "/keylinklister test [mapID level] — self-check + show the tooltip button for a keystone",
        "/keylinklister log [n] | diag | debug | logclear — diagnostic log (print, copy window, live echo, wipe)",
    },
}

if GetLocale() == "itIT" then
    L.LOADED = "v%s caricato — /keylinklister"
    L.LIST = LIST_GROUP or "Crea gruppo"
    L.RELIST = "Ri-crea gruppo"
    L.LISTED_SAME = "Già in lista"
    L.OPEN_PANEL = "Apri pannello"
    L.BTN_TT_PS = "Playstyle: %s"
    L.NO_KEY_HINT = "Nessuna keystone di questo dungeon nel gruppo: il pulsante apre il pannello Blizzard prefillato, digita lì il titolo e premi List Group."
    L.ERR_NOT_LEADER = "Non sei il leader del gruppo."
    L.ERR_INSTANCE_GROUP = "Sei in un gruppo istanza."
    L.ERR_FULL = "Il gruppo è già pieno."
    L.ERR_AUTH = "Nessun authenticator sull'account: puoi listare solo dungeon di cui possiedi la keystone."
    L.ERR_PLAYSTYLE = "Scegli prima un playstyle (pulsante a destra)."
    L.ERR_NO_ACTIVITY = "Nessuna activity del Group Finder trovata per questo dungeon."
    L.ERR_COMBAT = "Impossibile aprire il Group Finder in combattimento."
    L.LISTING = "Creo il gruppo %s +%d…"
    L.LISTED = "Gruppo in lista. Le candidature arrivano nel Group Finder."
    L.LIST_FAILED = "Listing diretto fallito (%s): clicca di nuovo il pulsante per aprire il pannello del Group Finder."
    L.CLIENT_REFUSED = "richiesta rifiutata dal client"
    L.CREATE_FAILED = "Il server ha rifiutato il listing."
    L.RELIST_WAIT = "Listing rimosso: clicca di nuovo il pulsante per creare quello nuovo."
    L.PANEL_ERR = "Impossibile prefillare il pannello del Group Finder (%s)."
    L.TYPE_TITLE = "Titolo suggerito: |cffffffff%s|r — scrivilo nel campo Title (il cursore è già lì) e premi List Group."
    L.TITLE_FMT = "Formato titolo: %s  (%%d = livello key, %%s = playstyle)"
    L.DELISTED = "Listing rimosso."
    L.NOT_LISTED = "Nessun listing attivo."
    L.PS_NONE = "(playstyle)"
    L.PS_TT = "Playstyle del listing (click per cambiare)"
    L.XF_ON = "Listing cross-fazione: ON"
    L.XF_OFF = "Listing cross-fazione: OFF"
    L.PRIV_ON = "Gruppo privato: ON"
    L.PRIV_OFF = "Gruppo privato: OFF"
    L.OPEN_ON = "Apri Group Finder dopo il listing: ON"
    L.OPEN_OFF = "Apri Group Finder dopo il listing: OFF"
    L.MODE = "Modalità: %s (direct = crea dal pulsante, panel = apre il pannello di creazione)"
    L.SCORE = "Rating M+ richiesto: %d"
    L.PS_SET = "Playstyle: %s"
    L.TEST_NOKEY = "Non possiedi keystone: prova con /keylinklister test <challengeMapID> <livello>."
    L.TEST_HDR = "auto-verifica"
    L.HELP = {
        "/keylinklister — questo aiuto",
        "/keylinklister playstyle [1-4] — mostra o imposta il playstyle del listing",
        "/keylinklister xfaction | private | open — attiva/disattiva opzioni",
        "/keylinklister mode direct|panel — crea direttamente o apri il pannello Blizzard",
        "/keylinklister score <n> — rating M+ richiesto ai candidati",
        "/keylinklister title <formato> — titolo suggerito per key non tue (default +%d; %s = playstyle)",
        "/keylinklister delist — rimuovi il tuo listing attivo",
        "/keylinklister status — stato corrente",
        "/keylinklister test [mapID livello] — auto-verifica + mostra il pulsante per una keystone",
        "/keylinklister log [n] | diag | debug | logclear — log diagnostico (stampa, finestra copiabile, echo live, svuota)",
    }
end

local function Print(msg)
    print("|cff33ccffKeyLinkLister|r " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- SavedVariables (account-wide)
-- ---------------------------------------------------------------------------

KeyLinkListerDB = KeyLinkListerDB or {}
local db

local function InitDB()
    KeyLinkListerDB = KeyLinkListerDB or {}
    db = KeyLinkListerDB
    -- ponytail: default Expert (4), il valore mostrato come "Competitive" nel client
    if db.playstyle == nil then db.playstyle = PS_MAX end
    if db.crossFaction == nil then db.crossFaction = true end
    if db.private == nil then db.private = false end
    if db.openFinder == nil then db.openFinder = true end
    if db.mode ~= "panel" then db.mode = "direct" end
    db.minScore = tonumber(db.minScore) or 0
end

local PS_FALLBACK = { "Learning", "Relaxed", "Serious", "Expert" }

local function PlaystyleName(ps)
    if not ps or ps == PS_NONE then return L.PS_NONE end
    return _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. ps] or PS_FALLBACK[ps] or tostring(ps)
end

-- ---------------------------------------------------------------------------
-- Log diagnostico persistente (KeyLinkListerDB.log): /kl log, /kl diag, /kl debug
-- ---------------------------------------------------------------------------

local LOG_MAX = 200
local logWindow = 0 -- GetTime() limite: messaggi di sistema/errore UI loggati solo dopo un click

local function T(v) return tostring(v) end

local function Log(line)
    if not db then return end
    db.log = db.log or {}
    line = date("%H:%M:%S") .. " " .. line
    db.log[#db.log + 1] = line
    while #db.log > LOG_MAX do table.remove(db.log, 1) end
    if db.debug then Print("|cff888888" .. line .. "|r") end
end

-- le funzioni di descrizione non devono mai rompere il flusso principale
local function SafeLog(fn)
    local ok, s = pcall(fn)
    Log(ok and s or ("log error: " .. T(s)))
end

local function DescribeActivity(activityID)
    local info = activityID and C_LFGList.GetActivityInfoTable(activityID)
    if not info then return "activity=" .. T(activityID) .. " info=nil" end
    return ("activity=%s '%s' short='%s' mapID=%s group=%s cat=%s M+=%s maxP=%s xf=%s filters=%s"):format(
        T(activityID), T(info.fullName), T(info.shortName), T(info.mapID), T(info.groupFinderActivityGroupID),
        T(info.categoryID), T(info.isMythicPlusActivity), T(info.maxNumPlayers), T(info.allowCrossFaction), T(info.filters))
end

local function DescribeState(activityID)
    local ownedMap = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local ownedLvl = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
    local oa, og, ol
    if C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel then
        oa, og, ol = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()
    end
    local active = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
    local auth = C_LFGList.IsPlayerAuthenticatedForLFG and C_LFGList.IsPlayerAuthenticatedForLFG(DUNGEON_CATEGORY)
    local keyFor = activityID and C_LFGList.GetKeystoneForActivity and C_LFGList.GetKeystoneForActivity(activityID)
    return ("auth=%s keyForActivity=%s ownedKey=%s/+%s ownedActivity=%s/%s/+%s inGroup=%s leader=%s members=%s instGroup=%s active=%s playstyle=%s xf=%s private=%s score=%s mode=%s")
        :format(T(auth), T(keyFor), T(ownedMap), T(ownedLvl), T(oa), T(og), T(ol),
            T(IsInGroup(CAT_HOME)), T(UnitIsGroupLeader("player", CAT_HOME)), T(GetNumGroupMembers(CAT_HOME)),
            T(IsInGroup(CAT_INSTANCE)), T(active and active.activityIDs and active.activityIDs[1]),
            T(db.playstyle), T(db.crossFaction), T(db.private), T(db.minScore), T(db.mode))
end

local function DescribeCreateData(d)
    return ("createData activityIDs={%s} autoAccept=%s xf=%s private=%s playstyle=%s general=%s score=%s ilvl=%s pvp=%s"):format(
        T(d.activityIDs and d.activityIDs[1]), T(d.isAutoAccept), T(d.isCrossFactionListing), T(d.isPrivateGroup),
        T(d.playstyle), T(d.generalPlaystyle), T(d.requiredDungeonScore), T(d.requiredItemLevel), T(d.requiredPvpRating))
end

-- ---------------------------------------------------------------------------
-- Keystone link -> activity del Group Finder
-- ---------------------------------------------------------------------------

-- |Hkeystone:itemID:challengeMapID:level:affix1:affix2:affix3:affix4|h
local function ParseKeystoneLink(link)
    if type(link) ~= "string" then return nil end
    local mapID, level = link:match("keystone:%d+:(%d+):(%d+)")
    if not mapID then return nil end
    return tonumber(mapID), tonumber(level)
end

local activityCache = {} -- challengeMapID -> { activityID, groupID, name, cands }

-- Tutte le activity M+ che corrispondono al dungeon (per mapID dell'istanza, locale-indipendente,
-- oppure per nome). Lo stesso dungeon può avere più activity (gruppi/stagioni diverse).
local function Candidates(instanceMapID, name)
    local seen, cands = {}, {}
    local function Scan(filters)
        local lists = {}
        local groups = C_LFGList.GetAvailableActivityGroups(DUNGEON_CATEGORY, filters) or {}
        for _, g in ipairs(groups) do
            lists[#lists + 1] = C_LFGList.GetAvailableActivities(DUNGEON_CATEGORY, g, filters) or {}
        end
        lists[#lists + 1] = C_LFGList.GetAvailableActivities(DUNGEON_CATEGORY, 0, filters) or {}
        for _, list in ipairs(lists) do
            for _, id in ipairs(list) do
                if not seen[id] then
                    local info = C_LFGList.GetActivityInfoTable(id)
                    if info and info.isMythicPlusActivity then
                        local byMap = instanceMapID and instanceMapID ~= 0 and info.mapID == instanceMapID
                        local byName = info.shortName == name or info.fullName == name
                            or (type(info.fullName) == "string" and info.fullName:find(name, 1, true))
                        if byMap or byName then
                            seen[id] = true
                            cands[#cands + 1] = {
                                id = id, group = info.groupFinderActivityGroupID or 0,
                                filters = info.filters or 0, byMap = byMap and true or false, fullName = info.fullName,
                            }
                        end
                    end
                end
            end
        end
    end
    Scan(bit.bor(FILTER_PVE, FILTER_SEASON))
    Scan(FILTER_PVE)
    return cands
end

-- Priorità: match per mapID > stesso gruppo dell'activity della key posseduta (è il gruppo che
-- Blizzard usa per i listing keystone) > flag CurrentSeason > ordine di enumerazione.
local function PickCandidate(cands)
    local ownedGroup
    if C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel then
        local _, g = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()
        ownedGroup = g
    end
    local best, bestScore = nil, -1
    for _, c in ipairs(cands) do
        local score = (c.byMap and 4 or 0)
            + ((ownedGroup and c.group == ownedGroup) and 2 or 0)
            + ((bit.band(c.filters, FILTER_SEASON) ~= 0) and 1 or 0)
        if score > bestScore then best, bestScore = c, score end
    end
    return best
end

local function ResolveActivity(challengeMapID)
    local hit = activityCache[challengeMapID]
    if hit then return hit.activityID, hit.groupID, hit.name end
    if not (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_LFGList) then return nil end
    local name, _, _, _, _, instanceMapID = C_ChallengeMode.GetMapUIInfo(challengeMapID)
    if not name then return nil end
    local cands = Candidates(instanceMapID, name)
    local best = PickCandidate(cands)
    if not best then return nil end
    activityCache[challengeMapID] = { activityID = best.id, groupID = best.group, name = name, cands = cands }
    return best.id, best.group, name
end

local function DescribeCandidates(challengeMapID)
    local hit = activityCache[challengeMapID]
    if not (hit and hit.cands) then return "candidates=?" end
    local parts = {}
    for _, c in ipairs(hit.cands) do
        local gname = C_LFGList.GetActivityGroupInfo and C_LFGList.GetActivityGroupInfo(c.group)
        parts[#parts + 1] = ("%s/g%s(%s)/f%s/%s"):format(T(c.id), T(c.group), T(gname), T(c.filters), c.byMap and "map" or "name")
    end
    return "candidates=[" .. table.concat(parts, " ") .. "]"
end

-- ---------------------------------------------------------------------------
-- Controlli: posso listare questa activity adesso?
-- ---------------------------------------------------------------------------

local function CanList(activityID)
    if IsInGroup(CAT_INSTANCE) then return false, L.ERR_INSTANCE_GROUP end
    if IsInGroup(CAT_HOME) and not UnitIsGroupLeader("player", CAT_HOME) then
        return false, L.ERR_NOT_LEADER
    end
    local info = C_LFGList.GetActivityInfoTable(activityID)
    local maxPlayers = info and info.maxNumPlayers or 0
    if maxPlayers > 0 and GetNumGroupMembers(CAT_HOME) >= maxPlayers then return false, L.ERR_FULL end
    -- Regola Blizzard (LFGListEntryCreation_UpdateValidState): senza authenticator un gruppo M+
    -- si può listare solo per un dungeon di cui si possiede la keystone.
    if not C_LFGList.IsPlayerAuthenticatedForLFG(DUNGEON_CATEGORY)
        and not C_LFGList.GetKeystoneForActivity(activityID) then
        return false, L.ERR_AUTH
    end
    if not db or db.playstyle == PS_NONE then return false, L.ERR_PLAYSTYLE end
    return true
end

-- ---------------------------------------------------------------------------
-- Listing diretto (SOLO da hardware event) e fallback sul pannello Blizzard
-- ---------------------------------------------------------------------------

local function BuildCreateData(activityID)
    local info = C_LFGList.GetActivityInfoTable(activityID)
    return {
        activityIDs = { activityID },
        isAutoAccept = false,
        isCrossFactionListing = (db.crossFaction and info and info.allowCrossFaction) and true or false,
        isPrivateGroup = db.private and true or false,
        playstyle = LEGACY_PS_NONE,
        generalPlaystyle = db.playstyle,
        requiredDungeonScore = db.minScore or 0,
        requiredItemLevel = 0,
        requiredPvpRating = 0,
    }
end

-- Titolo auto-generato (obbligatorio per le activity M+): SetEntryTitle e CreateListing sono
-- entrambe hardware-event e un evento si consuma con una chiamata (PremadeGroupsFilter:
-- "we already used our hardware event"). Quindi: titolo al click sul link / sul playstyle,
-- listing da solo al click sul pulsante.
local function SetTitle(activityID, groupID)
    return pcall(function()
        -- come LFGListEntryCreation_Clear: campi puliti (niente descrizioni vecchie), poi titolo
        if C_LFGList.ClearCreationTextFields then C_LFGList.ClearCreationTextFields() end
        C_LFGList.SetEntryTitle(activityID, groupID or 0, nil, db.playstyle)
    end)
end

-- Presuppone nessun listing attivo: RemoveListing è a sua volta hardware-event, quindi
-- il "re-list" avviene in due click (rimuovi, poi crea) — vedi OnListClick.
local function DoListing(activityID, groupID)
    local createData = BuildCreateData(activityID)
    Log("CreateListing #1 " .. DescribeCreateData(createData))
    local r1 = C_LFGList.CreateListing(createData)
    Log("CreateListing #1 -> " .. T(r1))
    if r1 then return true end
    -- false = nessun titolo valido (campi puliti nel frattempo): riprova nello stesso evento
    local okT, errT = SetTitle(activityID, groupID)
    Log("retry SetEntryTitle -> " .. T(okT) .. " " .. T(errT))
    local r2 = C_LFGList.CreateListing(createData)
    Log("CreateListing #2 -> " .. T(r2))
    return r2
end

local function OpenFinder()
    if InCombatLockdown() then Print(L.ERR_COMBAT) return false end
    if LFGListUtil_OpenBestWindow then
        LFGListUtil_OpenBestWindow()
    elseif PVEFrame_ShowFrame then
        PVEFrame_ShowFrame("GroupFinderFrame", "LFGListPVEStub")
    end
    return true
end

-- Apre Dungeons & Raids > Premade > Start a Group con dungeon e playstyle preselezionati.
-- Chiama funzioni Blizzard da codice addon (taint sul pannello): usarlo solo da un click e
-- senza listing attivo (il pannello di creazione è invalido con un listing in corso).
-- Forza la finestra PvE: LFGListUtil_OpenBestWindow aprirebbe quella PvP se fosse l'ultima usata
-- e Show(…, baseFilters PvP, Dungeons) farebbe assert dentro LFGListUtil_AugmentWithBest.
-- Titolo suggerito per il pannello: db.titleFormat, %d = livello key, %s = playstyle.
local function SuggestedTitle(level)
    local fmt = db.titleFormat or "+%d"
    local ok, s = pcall(string.format, fmt, level or 0, PlaystyleName(db.playstyle))
    return (ok and s ~= "") and s or ("+" .. T(level or 0))
end

-- Ogni LFGListEntryCreation_Select termina con C_LFGList.SetEntryTitle (hardware-event, una
-- chiamata per click): LFGListEntryCreation_Show ne farebbe due (auto-best + key posseduta) e la
-- seconda viene bloccata ("Interface action failed because of an AddOn"). Quindi: un solo Select.
local function OpenCreationPanel(activityID, groupID, level)
    if InCombatLockdown() then Print(L.ERR_COMBAT) return end
    if not PVEFrame_ShowFrame then return end
    PVEFrame_ShowFrame("GroupFinderFrame", "LFGListPVEStub")
    local frame = LFGListFrame
    local ec = frame and frame.EntryCreation
    if not (ec and LFGListEntryCreation_Select and LFGListEntryCreation_Clear and LFGListFrame_SetActivePanel) then
        return
    end
    local ok, err = pcall(function()
        if LFGListCategorySelection_SelectCategory and frame.CategorySelection then
            LFGListCategorySelection_SelectCategory(frame.CategorySelection, DUNGEON_CATEGORY, 0)
        end
        local base = frame.baseFilters or FILTER_PVE -- deve coincidere con LFGListFrame.baseFilters
        -- Come il keepOldData di LFGListEntryCreation_Show: stesso dungeon già selezionato => niente
        -- Clear/Select, così il titolo digitato a mano resta nel campo sicuro (utile per ri-listare).
        local keepOldData = ec.selectedActivity == activityID and ec.selectedCategory == DUNGEON_CATEGORY
            and ec.baseFilters == base and not ec.editMode
        if not keepOldData then
            ec.baseFilters = base
            LFGListEntryCreation_Clear(ec)
            ec.editMode = false
            ec.generalPlaystyle = db.playstyle -- prima del Select: il titolo nasce già con il playstyle
            LFGListEntryCreation_Select(ec, 0, DUNGEON_CATEGORY, groupID or 0, activityID)
        end
        Log("OpenCreationPanel keepOldData=" .. T(keepOldData))
        -- quello che LFGListEntryCreation_SetEditMode(false) farebbe, senza il suo secondo Select
        if ec.GroupDropdown and ec.GroupDropdown.Enable then ec.GroupDropdown:Enable() end
        if ec.ActivityDropdown and ec.ActivityDropdown.Enable then ec.ActivityDropdown:Enable() end
        if ec.PlayStyleDropdown and ec.PlayStyleDropdown.GenerateMenu then ec.PlayStyleDropdown:GenerateMenu() end
        if ec.ListGroupButton and LIST_GROUP then ec.ListGroupButton:SetText(LIST_GROUP) end
        if ec.Name and ec.Name.SetEnabled and C_LFGList.IsPlayerAuthenticatedForLFG(DUNGEON_CATEGORY) then
            ec.Name:SetEnabled(true) -- con authenticator il titolo è modificabile
        end
        local ci = C_LFGList.GetLfgCategoryInfo and C_LFGList.GetLfgCategoryInfo(DUNGEON_CATEGORY)
        if ec.Label and ci then ec.Label:SetText(ci.name) end
        LFGListFrame_SetActivePanel(frame, ec)
        -- Titolo: senza key propria il prebuilt è vuoto e l'editbox è securityDisableSetText
        -- (XML Blizzard): SetText da addon di norma viene ignorato. Provo comunque; se resta
        -- vuoto, il suggerimento va nel placeholder, il cursore nel campo, e lo dico in chat.
        local name = ec.Name
        if name and name.GetText then
            -- Invio nel campo Title = List Group (Enter è un hardware event, come il click):
            -- il gesto diventa "digita +15, Invio". Hook una sola volta.
            if not name._klEnterHooked and name.HookScript then
                name._klEnterHooked = true
                local function OnEnter()
                    local btn = ec.ListGroupButton
                    if btn and btn.IsEnabled and btn:IsEnabled() and btn.Click then
                        Log("Enter in Title -> ListGroupButton:Click()")
                        btn:Click()
                    end
                end
                if name.GetScript and name:GetScript("OnEnterPressed") then
                    name:HookScript("OnEnterPressed", OnEnter)
                else
                    name:SetScript("OnEnterPressed", OnEnter)
                end
            end
            if name.Instructions and name._klOrigInstructions then
                name.Instructions:SetText(name._klOrigInstructions)
            end
            if (name:GetText() or "") == "" then
                local title = SuggestedTitle(level)
                pcall(name.SetText, name, title)
                local applied = (name:GetText() == title)
                if not applied and name.Insert then -- metodo diverso da SetText: forse non coperto dal flag
                    pcall(name.Insert, name, title)
                    applied = (name:GetText() == title)
                    Log("Insert fallback applied=" .. T(applied))
                end
                if not applied and name.Instructions and name.Instructions.SetText then
                    name._klOrigInstructions = name._klOrigInstructions or name.Instructions:GetText()
                    name.Instructions:SetText(title)
                end
                if LFGListEntryCreation_UpdateValidState then LFGListEntryCreation_UpdateValidState(ec) end
                if name.SetFocus then name:SetFocus() end
                Log("title '" .. title .. "' applied=" .. T(applied))
                if not applied then Print(L.TYPE_TITLE:format(title)) end
            end
        end
    end)
    Log("OpenCreationPanel -> " .. T(ok) .. " " .. T(err))
    if not ok then Print(L.PANEL_ERR:format(tostring(err))) end
end

-- ---------------------------------------------------------------------------
-- Riga con pulsanti sotto ItemRefTooltip
-- ---------------------------------------------------------------------------

local row, listBtn, psBtn
local current -- { mapID, level, activityID, groupID, name, forcePanel }
local pendingOpen = 0 -- GetTime() limite entro cui ACTIVE_ENTRY_UPDATE è conseguenza nostra

-- Il listing diretto via API funziona solo con una keystone di quel dungeon nel gruppo
-- (altrimenti il server lo rifiuta: LFG_LIST_ENTRY_CREATION_FAILED). Senza key, con
-- authenticator, la via è il pannello Blizzard prefillato dove si digita il titolo.
local function NeedsPanel()
    if not current then return false end
    if db.mode == "panel" or current.forcePanel then return true end
    if not C_LFGList.GetKeystoneForActivity or C_LFGList.GetKeystoneForActivity(current.activityID) then
        return false
    end
    -- senza key di quel dungeon: da soli il server rifiuta sempre (osservato); in gruppo tento il
    -- listing diretto (la key può averla un membro), e se fallisce il click dopo apre il pannello
    return GetNumGroupMembers(CAT_HOME) == 0
end

local function RefreshRow()
    if not row then return end
    if not current then row:Hide() return end
    local ok, reason = CanList(current.activityID)
    local active = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
    local sameListed = active and active.activityIDs and active.activityIDs[1] == current.activityID
    local label
    if sameListed then
        label = L.LISTED_SAME
    elseif active then
        label = L.RELIST
    elseif NeedsPanel() then
        label = L.OPEN_PANEL
    else
        label = L.LIST
    end
    listBtn:SetText(label)
    listBtn.reason = (not ok) and reason or nil
    listBtn:SetEnabled(ok and not sameListed)
    psBtn:SetText(PlaystyleName(db.playstyle))
    row:Show()
end

-- Un click = un hardware event = una sola chiamata ristretta (RemoveListing, CreateListing,
-- SetEntryTitle…). Perciò: listing attivo -> questo click lo rimuove e basta; il prossimo crea.
local function OnListClick()
    if not current then return end
    logWindow = GetTime() + OPEN_WINDOW
    SafeLog(function() return "CLICK " .. DescribeActivity(current.activityID) .. " | " .. DescribeState(current.activityID) end)
    if C_LFGList.HasActiveEntryInfo() then
        C_LFGList.RemoveListing()
        Log("RemoveListing called (relist step 1)")
        Print(L.RELIST_WAIT)
        RefreshRow() -- l'etichetta torna "List Group" all'arrivo di LFG_LIST_ACTIVE_ENTRY_UPDATE
        return
    end
    local ok, reason = CanList(current.activityID)
    if not ok then Log("CanList false: " .. T(reason)) Print(reason) return end
    if NeedsPanel() then
        Log("OpenCreationPanel (mode=" .. T(db.mode) .. " forcePanel=" .. T(current.forcePanel) .. ")")
        OpenCreationPanel(current.activityID, current.groupID, current.level)
        return
    end
    Print(L.LISTING:format(current.name, current.level))
    local okCall, result = pcall(DoListing, current.activityID, current.groupID)
    Log("DoListing -> ok=" .. T(okCall) .. " result=" .. T(result))
    if okCall and result then
        pendingOpen = GetTime() + OPEN_WINDOW
    else
        -- niente fallback nello stesso click (evento già speso): il prossimo click apre il pannello
        current.forcePanel = true
        Print(L.LIST_FAILED:format(okCall and L.CLIENT_REFUSED or tostring(result)))
    end
    RefreshRow()
end

local function CyclePlaystyle()
    local ps = (db.playstyle or PS_NONE) + 1
    if ps > PS_MAX then ps = 1 end
    db.playstyle = ps
    -- click = hardware event: aggiorna subito il titolo con il nuovo playstyle
    if current and not NeedsPanel() and CanList(current.activityID) then
        SetTitle(current.activityID, current.groupID)
    end
    RefreshRow()
end

local function BuildRow()
    if row then return end
    local template = (TooltipBackdropTemplateMixin and "TooltipBackdropTemplate") or nil
    row = CreateFrame("Frame", "KeyLinkListerRow", ItemRefTooltip, template)
    row:SetPoint("TOPLEFT", ItemRefTooltip, "BOTTOMLEFT", 0, -2)
    row:SetPoint("TOPRIGHT", ItemRefTooltip, "BOTTOMRIGHT", 0, -2)
    row:SetHeight(34)
    if not template then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.85)
    end

    psBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    psBtn:SetSize(104, 22)
    psBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    psBtn:SetScript("OnClick", CyclePlaystyle)
    psBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L.PS_TT, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    psBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    listBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    listBtn:SetHeight(22)
    listBtn:SetPoint("LEFT", row, "LEFT", 6, 0)
    listBtn:SetPoint("RIGHT", psBtn, "LEFT", -4, 0)
    listBtn:SetScript("OnClick", OnListClick)
    -- il motivo del blocco deve comparire anche a pulsante disabilitato
    if listBtn.SetMotionScriptsWhileDisabled then listBtn:SetMotionScriptsWhileDisabled(true) end
    listBtn:SetScript("OnEnter", function(self)
        if not current then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(("%s +%d"):format(current.name, current.level), 1, 1, 1)
        GameTooltip:AddLine(L.BTN_TT_PS:format(PlaystyleName(db.playstyle)), 0.7, 0.7, 0.7)
        if C_LFGList.GetKeystoneForActivity and not C_LFGList.GetKeystoneForActivity(current.activityID) then
            GameTooltip:AddLine(L.NO_KEY_HINT, 1, 0.8, 0.3, true)
        end
        if self.reason then GameTooltip:AddLine(self.reason, 1, 0.3, 0.3, true) end
        GameTooltip:Show()
    end)
    listBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:Hide()
end

-- Post-hook: dopo SetHyperlink il tooltip è mostrato (nuovo link) o nascosto (stesso link = toggle).
local function OnItemRefHyperlink(tooltip, link)
    if not row then return end
    local mapID, level = ParseKeystoneLink(link)
    if not mapID or not tooltip:IsShown() then
        current = nil
        row:Hide()
        return
    end
    local activityID, groupID, name = ResolveActivity(mapID)
    if not activityID then
        current = nil
        row:Hide()
        Print(L.ERR_NO_ACTIVITY)
        return
    end
    current = { mapID = mapID, level = level or 0, activityID = activityID, groupID = groupID, name = name }
    SafeLog(function()
        local oa, og = nil, nil
        if C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel then oa, og = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel() end
        local ogName = og and C_LFGList.GetActivityGroupInfo and C_LFGList.GetActivityGroupInfo(og)
        return ("LINK %s -> map=%s lvl=%s name='%s' | %s | %s | %s | ownedGroupName=%s"):format(T(link), T(mapID), T(level), T(name),
            DescribeActivity(activityID), DescribeCandidates(mapID), DescribeState(activityID), T(ogName))
    end)
    -- siamo dentro il click sul link (hardware event): imposta ora il titolo del listing
    local ok, reason = CanList(activityID)
    if ok and not NeedsPanel() then
        local okT, errT = SetTitle(activityID, groupID)
        local match = C_LFGList.DoesEntryTitleMatchPrebuiltTitle
            and C_LFGList.DoesEntryTitleMatchPrebuiltTitle(activityID, groupID or 0, LEGACY_PS_NONE, db.playstyle)
        Log("SetEntryTitle at link -> " .. T(okT) .. " " .. T(errT) .. " titleMatchesPrebuilt=" .. T(match))
    else
        Log("no title at link: mode=" .. T(db.mode) .. " canList=" .. T(ok) .. " " .. T(reason))
    end
    RefreshRow()
end

local function InstallHooks()
    if not ItemRefTooltip then return false end
    hooksecurefunc(ItemRefTooltip, "SetHyperlink", OnItemRefHyperlink)
    local function Clear()
        current = nil
        if row then row:Hide() end
    end
    ItemRefTooltip:HookScript("OnHide", Clear)
    -- contenuto sostituito senza SetHyperlink (es. link rating M+): il post-hook lo rimostra se serve
    ItemRefTooltip:HookScript("OnTooltipCleared", Clear)
    return true
end

-- ---------------------------------------------------------------------------
-- Slash
-- ---------------------------------------------------------------------------

local function Status()
    local active = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
    Print(("v%s mode=%s playstyle=%s xfaction=%s private=%s open=%s score=%d listed=%s auth=%s")
        :format(VERSION, db.mode, PlaystyleName(db.playstyle), tostring(db.crossFaction),
            tostring(db.private), tostring(db.openFinder), db.minScore,
            tostring(active and active.activityIDs and active.activityIDs[1] or false),
            tostring(C_LFGList.IsPlayerAuthenticatedForLFG(DUNGEON_CATEGORY))))
end

-- Auto-verifica: la mia risoluzione keystone->activity deve coincidere con quella Blizzard
-- per la key che possiedo; poi mostra davvero il tooltip (e il pulsante) per quella key.
local function SelfTest(arg)
    local mapID, level = arg:match("^(%d+)%s+(%d+)$")
    mapID, level = tonumber(mapID), tonumber(level)
    if not mapID then
        mapID = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        level = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or 0
        if not mapID or mapID == 0 then Print(L.TEST_NOKEY) return end
        local blzActivity, blzGroup = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()
        local mine, myGroup, name = ResolveActivity(mapID)
        local same = (blzActivity == mine) and "|cff00ff00OK|r" or "|cffff4040MISMATCH|r"
        Print(("%s: map %d (%s) -> mine %s/%s, blizzard %s/%s %s"):format(L.TEST_HDR, mapID,
            tostring(name), tostring(mine), tostring(myGroup), tostring(blzActivity), tostring(blzGroup), same))
    end
    local ok, reason = true, nil
    local activityID = ResolveActivity(mapID)
    if activityID then ok, reason = CanList(activityID) end
    Print(("%s: activity=%s canList=%s %s"):format(L.TEST_HDR, tostring(activityID), tostring(ok), reason or ""))
    if ItemRefTooltip then
        local link = ("keystone:180653:%d:%d:0:0:0:0"):format(mapID, level or 0)
        if not ItemRefTooltip:IsShown() then ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
        ItemRefTooltip:SetHyperlink(link)
    end
end

-- Finestra con il log copiabile (CTRL+A, CTRL+C) da incollare in una segnalazione.
local diag
local function ShowDiag()
    if not diag then
        diag = CreateFrame("Frame", "KeyLinkListerDiag", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        diag:SetSize(720, 440)
        diag:SetPoint("CENTER")
        diag:SetFrameStrata("DIALOG")
        diag:SetMovable(true)
        diag:EnableMouse(true)
        diag:RegisterForDrag("LeftButton")
        diag:SetScript("OnDragStart", diag.StartMoving)
        diag:SetScript("OnDragStop", diag.StopMovingOrSizing)
        if diag.SetBackdrop then
            diag:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            diag:SetBackdropColor(0, 0, 0, 0.92)
        end
        local close = CreateFrame("Button", nil, diag, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        local title = diag:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("KeyLinkLister diag — CTRL+A, CTRL+C")
        local scroll = CreateFrame("ScrollFrame", nil, diag, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -30)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject("ChatFontSmall")
        edit:SetWidth(660)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        scroll:SetScrollChild(edit)
        diag.edit = edit
    end
    local v, build, _, iface = GetBuildInfo()
    local lines = { ("KeyLinkLister v%s | client %s (%s) iface %s | locale %s"):format(VERSION, T(v), T(build), T(iface), T(GetLocale())) }
    for _, l in ipairs(db.log or {}) do lines[#lines + 1] = l end
    diag.edit:SetText(table.concat(lines, "\n"))
    diag:Show()
    diag.edit:SetFocus()
    diag.edit:HighlightText()
end

SLASH_KEYLINKLISTER1 = "/keylinklister"
SLASH_KEYLINKLISTER2 = "/kll"
SLASH_KEYLINKLISTER3 = "/kl"
SlashCmdList.KEYLINKLISTER = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    if not db then Print("not initialized") return end
    if cmd == "" or cmd == "help" then
        for _, line in ipairs(L.HELP) do print("  " .. line) end
    elseif cmd == "playstyle" or cmd == "ps" then
        local n = tonumber(rest)
        if n and n >= 1 and n <= PS_MAX then db.playstyle = n end
        Print(L.PS_SET:format(PlaystyleName(db.playstyle)))
        -- slash = hardware event: titolo rigenerato con il nuovo playstyle
        if current and not NeedsPanel() and CanList(current.activityID) then
            SetTitle(current.activityID, current.groupID)
        end
        RefreshRow()
    elseif cmd == "xfaction" then
        db.crossFaction = not db.crossFaction
        Print(db.crossFaction and L.XF_ON or L.XF_OFF)
    elseif cmd == "private" then
        db.private = not db.private
        Print(db.private and L.PRIV_ON or L.PRIV_OFF)
    elseif cmd == "open" then
        db.openFinder = not db.openFinder
        Print(db.openFinder and L.OPEN_ON or L.OPEN_OFF)
    elseif cmd == "mode" then
        if rest == "direct" or rest == "panel" then db.mode = rest end
        Print(L.MODE:format(db.mode))
        RefreshRow()
    elseif cmd == "score" then
        db.minScore = math.max(0, math.floor(tonumber(rest) or 0))
        Print(L.SCORE:format(db.minScore))
    elseif cmd == "title" then
        if rest ~= "" then db.titleFormat = rest end
        Print(L.TITLE_FMT:format(db.titleFormat or "+%d") .. "  → " .. SuggestedTitle(current and current.level or 15))
    elseif cmd == "delist" then
        if C_LFGList.HasActiveEntryInfo() then
            C_LFGList.RemoveListing()
            Print(L.DELISTED)
        else
            Print(L.NOT_LISTED)
        end
    elseif cmd == "status" then
        Status()
    elseif cmd == "test" then
        SelfTest(rest)
    elseif cmd == "log" then
        local n = tonumber(rest) or 30
        local lg = db.log or {}
        for i = math.max(1, #lg - n + 1), #lg do print("  " .. lg[i]) end
        Print(#lg .. " log lines (/keylinklister diag to copy, /keylinklister logclear to wipe)")
    elseif cmd == "logclear" then
        db.log = {}
        Print("log cleared")
    elseif cmd == "debug" then
        db.debug = not db.debug
        Print("debug echo: " .. (db.debug and "ON" or "OFF"))
    elseif cmd == "diag" then
        ShowDiag()
    else
        for _, line in ipairs(L.HELP) do print("  " .. line) end
    end
end

-- ---------------------------------------------------------------------------
-- Eventi (handler PRIMA delle registrazioni; registrazioni LFG deferite)
-- ---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
    local arg1 = ...
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            InitDB()
            ev:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        if not db then InitDB() end
        local ok, err = pcall(function()
            BuildRow()
            InstallHooks()
        end)
        if not ok then Print("|cffff4040build error:|r " .. tostring(err)) end
        C_Timer.After(0, function()
            ev:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
            ev:RegisterEvent("LFG_LIST_ENTRY_CREATION_FAILED")
            ev:RegisterEvent("UI_ERROR_MESSAGE")
            ev:RegisterEvent("CHAT_MSG_SYSTEM")
        end)
        Print(L.LOADED:format(VERSION))
    elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        local createdNew = arg1
        SafeLog(function()
            local active = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
            return "EVENT LFG_LIST_ACTIVE_ENTRY_UPDATE created=" .. T(createdNew) .. " active=" .. T(active and active.activityIDs and active.activityIDs[1])
        end)
        if createdNew and GetTime() < pendingOpen then
            pendingOpen = 0
            Print(L.LISTED)
            if db.openFinder then OpenFinder() end
        end
        RefreshRow()
    elseif event == "LFG_LIST_ENTRY_CREATION_FAILED" then
        Log("EVENT LFG_LIST_ENTRY_CREATION_FAILED " .. T(arg1))
        if GetTime() < pendingOpen then
            pendingOpen = 0
            Print(L.CREATE_FAILED)
            RefreshRow()
        end
    elseif event == "UI_ERROR_MESSAGE" then
        if GetTime() < logWindow then
            local errType, msg = ...
            Log("UI_ERROR_MESSAGE " .. T(errType) .. " '" .. T(msg) .. "'")
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        if GetTime() < logWindow then Log("SYSTEM '" .. T(arg1) .. "'") end
    end
end)
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")

-- Namespace di debug/test (/dump KeyLinkLister)
KeyLinkLister = {
    version = VERSION,
    ParseKeystoneLink = ParseKeystoneLink,
    ResolveActivity = ResolveActivity,
    CanList = CanList,
    BuildCreateData = BuildCreateData,
    SetTitle = SetTitle,
    SuggestedTitle = SuggestedTitle,
    DoListing = DoListing,
    OnItemRefHyperlink = OnItemRefHyperlink,
    RefreshRow = RefreshRow,
    InitDB = InitDB,
    ClearCache = function() wipe(activityCache) end,
    GetCurrent = function() return current end,
    GetCandidates = function(mapID) local h = activityCache[mapID]; return h and h.cands end,
    GetRow = function() return row, listBtn, psBtn end,
}
