"""Carica il VERO KeyLinkLister.lua in lupa con stub WoW e verifica: parse link,
risoluzione keystone->activity (per mapID e per nome), regole CanList,
createData, flusso hook tooltip (mostra/nasconde riga) e slash.

Uso: python tools/test_keylinklister.py   (dalla root del repo)
"""
import io
import os

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = io.open(os.path.join(ROOT, "KeyLinkLister.lua"), encoding="utf-8").read()

lua = LuaRuntime(unpack_returned_tuples=True)

# ---- stub ambiente WoW (solo ciò che l'addon tocca) -------------------------
lua.execute(r"""
printed = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring(select(i, ...)) end printed[#printed+1] = table.concat(t, " ") end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
GetLocale = function() return "enUS" end
GetTime = function() return now or 1000 end
InCombatLockdown = function() return false end
C_Timer = { After = function(_, fn) fn() end }
date = function() return "00:00:00" end
GetBuildInfo = function() return "12.1.0", "69587", "Sep 1 2026", 120100 end
bit = {
    bor = function(a, b) return a + b end, -- bit disgiunti nei test
    band = function(a, b)
        local r, p = 0, 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then r = r + p end
            a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
        end
        return r
    end,
}
Enum = {
    LFGListFilter = { PvE = 4 },
    LFGEntryPlaystyle = { None = 0 },
    LFGEntryGeneralPlaystyle = { None = 0, Learning = 1, FunRelaxed = 2, FunSerious = 3, Expert = 4 },
}
GROUP_FINDER_CATEGORY_ID_DUNGEONS = 2
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
GROUP_FINDER_GENERAL_PLAYSTYLE4 = "Competitive"
SlashCmdList = {}
UIParent = {}

-- stato di gruppo controllabile dai test
group = { home = false, instance = false, leader = true, members = 1 }
IsInGroup = function(cat) if cat == 2 then return group.instance end return group.home end
UnitIsGroupLeader = function() return group.leader end
GetNumGroupMembers = function() return group.members end

-- frame stub generico: metodi no-op + stato minimo
local function Frame(name)
    local f = { _name = name, _shown = false, _scripts = {}, _enabled = true, _text = "", _events = {} }
    f.Show = function(s) s._shown = true end
    f.Hide = function(s) s._shown = false; if s._scripts.OnHide then s._scripts.OnHide(s) end end
    f.IsShown = function(s) return s._shown end
    f.SetText = function(s, t) s._text = t end
    f.GetText = function(s) return s._text end
    f.SetEnabled = function(s, e) s._enabled = e and true or false end
    f.IsEnabled = function(s) return s._enabled end
    f.SetScript = function(s, k, fn) s._scripts[k] = fn end
    f.HookScript = function(s, k, fn) local o = s._scripts[k]; s._scripts[k] = function(...) if o then o(...) end fn(...) end end
    f.GetScript = function(s, k) return s._scripts[k] end
    f.RegisterEvent = function(s, e) s._events = s._events or {}; s._events[e] = true end
    f.UnregisterEvent = function(s, e) if s._events then s._events[e] = nil end end
    f.CreateTexture = function() return { SetAllPoints = function() end, SetColorTexture = function() end } end
    -- campi di stato (prefisso _) restano nil se assenti; tutto il resto è un metodo no-op
    setmetatable(f, { __index = function(_, k)
        if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
        return function() end
    end })
    return f
end
frames = {}
CreateFrame = function(kind, name, parent, template)
    local f = Frame(name or kind)
    frames[#frames+1] = f
    return f
end
GameTooltip = Frame("GameTooltip")
ItemRefTooltip = Frame("ItemRefTooltip")
-- SetHyperlink reale: stesso link => toggle off, come ItemRefTooltipMixin
ItemRefTooltip.SetHyperlink = function(s, link)
    if s._shown and s._link == link then s:Hide(); s._link = nil; return false end
    s._link = link; s._shown = true; return true
end
hooksecurefunc = function(tbl, name, fn)
    local orig = tbl[name]
    tbl[name] = function(...) local r = orig(...); fn(...); return r end
end

-- Group Finder: due activity M+ (una matcha per mapID, una solo per nome) + una M0
activities = {
    [100] = { fullName = "Temple of Sethraliss (Mythic Keystone)", shortName = "Mythic+", isMythicPlusActivity = true, mapID = 1877, groupFinderActivityGroupID = 10, maxNumPlayers = 5, allowCrossFaction = true, categoryID = 2, filters = 101 },
    [101] = { fullName = "Temple of Sethraliss", shortName = "Temple of Sethraliss", isMythicPlusActivity = false, mapID = 1877, groupFinderActivityGroupID = 10, maxNumPlayers = 5, allowCrossFaction = true, categoryID = 2, filters = 4 },
    [102] = { fullName = "The Underrot (Mythic Keystone)", shortName = "Mythic+", isMythicPlusActivity = true, mapID = 0, groupFinderActivityGroupID = 10, maxNumPlayers = 5, allowCrossFaction = false, categoryID = 2, filters = 4 },
    -- doppione dello stesso dungeon in un altro gruppo (stagione diversa), senza flag CurrentSeason
    [103] = { fullName = "Temple of Sethraliss (Mythic Keystone)", shortName = "Mythic+", isMythicPlusActivity = true, mapID = 1877, groupFinderActivityGroupID = 20, maxNumPlayers = 5, allowCrossFaction = true, categoryID = 2, filters = 4 },
}
maps = {
    [250] = { name = "Temple of Sethraliss", mapID = 1877 },
    [251] = { name = "The Underrot", mapID = 1841 },
}
lfg = { authenticated = false, ownedKeystones = {}, active = nil, calls = {} }
C_ChallengeMode = {
    GetMapUIInfo = function(id) local m = maps[id]; if not m then return nil end return m.name, id, 1800, 0, 0, m.mapID end,
}
C_LFGList = {
    GetAvailableActivityGroups = function() return { 20, 10 } end,
    GetAvailableActivities = function(_, g) if g == 10 then return { 101, 100, 102 } elseif g == 20 then return { 103 } end return {} end,
    GetActivityGroupInfo = function(g) return "Group" .. tostring(g), g end,
    GetOwnedKeystoneActivityAndGroupAndLevel = function() return 999, lfg.ownedGroup, 10 end,
    GetActivityInfoTable = function(id) return activities[id] end,
    IsPlayerAuthenticatedForLFG = function() return lfg.authenticated end,
    GetKeystoneForActivity = function(id) return lfg.ownedKeystones[id] end,
    HasActiveEntryInfo = function() return lfg.active ~= nil end,
    GetActiveEntryInfo = function() return lfg.active end,
    RemoveListing = function() lfg.calls[#lfg.calls+1] = "RemoveListing" end, -- asincrono: active resta finché il server conferma
    SetEntryTitle = function(a, g, ps, gps) lfg.calls[#lfg.calls+1] = ("SetEntryTitle:%s:%s:%s:%s"):format(a, g, tostring(ps), gps) end,
    CreateListing = function(d) lfg.calls[#lfg.calls+1] = "CreateListing"; lfg.lastCreate = d; return true end,
}
""")

# carica l'addon vero come farebbe il client (vararg = nome addon)
loader = lua.eval("function(src) local fn = assert(loadstring or load)(src, '=KeyLinkLister.lua') return fn end")
chunk = loader(SRC)
chunk("KeyLinkLister")

g = lua.globals()
KL = g.KeyLinkLister
assert KL is not None, "namespace KeyLinkLister non esportato"

# simula ADDON_LOADED + PLAYER_LOGIN sul frame eventi (l'ultimo Frame creato prima dei pulsanti è ev)
lua.execute("""
for _, f in ipairs(frames) do
    if f._events and f._events.ADDON_LOADED then ev = f end
end
assert(ev, "frame eventi non trovato")
ev._scripts.OnEvent(ev, "ADDON_LOADED", "KeyLinkLister")
ev._scripts.OnEvent(ev, "PLAYER_LOGIN")
""")
assert any("loaded" in p for p in g.printed.values()), list(g.printed.values())
assert g.KeyLinkListerDB.playstyle == 4 and g.KeyLinkListerDB.mode == "direct"

# ---- parse -------------------------------------------------------------------
m, lvl = KL.ParseKeystoneLink("|cffa335ee|Hkeystone:180653:250:12:10:9:152:0|h[Keystone: Temple of Sethraliss (12)]|h|r")
assert (m, lvl) == (250, 12), (m, lvl)
assert KL.ParseKeystoneLink("item:180653:0:0") is None
assert KL.ParseKeystoneLink(None) is None

# ---- resolve: per mapID batte la M0 omonima; tra doppioni vince CurrentSeason; per nome se mapID manca
a, grp, name = KL.ResolveActivity(250)
assert (a, grp, name) == (100, 10, "Temple of Sethraliss"), (a, grp, name)
assert len(KL.GetCandidates(250)) == 2                        # 100 e 103, mai la M0 101
a2, grp2, name2 = KL.ResolveActivity(251)
assert (a2, grp2) == (102, 10), (a2, grp2)
assert KL.ResolveActivity(999) is None
# il gruppo dell'activity della key posseduta batte il flag CurrentSeason
lua.execute("lfg.ownedGroup = 20"); KL.ClearCache()
assert KL.ResolveActivity(250)[0] == 103
lua.execute("lfg.ownedGroup = nil"); KL.ClearCache()
assert KL.ResolveActivity(250)[0] == 100

# ---- CanList: ordine dei controlli ------------------------------------------
ok, why = KL.CanList(100)
assert ok is False and "authenticator" in why, why           # no auth, no key
lua.execute("lfg.ownedKeystones[100] = 12")
assert KL.CanList(100) is True                                # possiedo la key
lua.execute("lfg.ownedKeystones[100] = nil; lfg.authenticated = true")
assert KL.CanList(100) is True                                # authenticator
lua.execute("group.home = true; group.leader = false")
ok, why = KL.CanList(100); assert ok is False and "leader" in why, why
lua.execute("group.leader = true; group.members = 5")
ok, why = KL.CanList(100); assert ok is False and "full" in why, why
lua.execute("group.members = 3; group.instance = true")
ok, why = KL.CanList(100); assert ok is False and "instance" in why, why
lua.execute("group.instance = false; KeyLinkListerDB.playstyle = 0")
ok, why = KL.CanList(100); assert ok is False and "playstyle" in why, why
lua.execute("KeyLinkListerDB.playstyle = 4")

# ---- createData: forma esatta attesa da C_LFGList.CreateListing (11.1+) -----
d = KL.BuildCreateData(100)
assert list(d.activityIDs.values()) == [100]
assert d.generalPlaystyle == 4 and d.playstyle == 0
assert d.isCrossFactionListing is True and d.isPrivateGroup is False
assert d.requiredDungeonScore == 0 and d.requiredItemLevel == 0 and d.requiredPvpRating == 0
d2 = KL.BuildCreateData(102)                                  # activity senza cross-faction
assert d2.isCrossFactionListing is False

# ---- DoListing: una sola chiamata ristretta per hardware event ------------------
lua.execute("lfg.calls = {}")
assert KL.DoListing(100, 10) is True
calls = list(g.lfg.calls.values())
assert calls == ["CreateListing"], calls                      # titolo già impostato al click sul link, mai RemoveListing qui
# primo CreateListing false (titolo perso) => retry titolo + listing nello stesso evento
lua.execute("""
lfg.calls = {}; local n = 0
C_LFGList.CreateListing = function(d) n = n + 1; lfg.calls[#lfg.calls+1] = "CreateListing"; lfg.lastCreate = d; return n > 1 end
""")
assert KL.DoListing(100, 10) is True
assert list(g.lfg.calls.values()) == ["CreateListing", "SetEntryTitle:100:10:nil:4", "CreateListing"], list(g.lfg.calls.values())
lua.execute('C_LFGList.CreateListing = function(d) lfg.calls[#lfg.calls+1] = "CreateListing"; lfg.lastCreate = d; return true end')

# ---- hook tooltip: link keystone mostra la riga, altro link / toggle la nasconde
row, listBtn, psBtn = KL.GetRow()
lua.execute("lfg.ownedKeystones[100] = 12")                  # key posseduta -> listing diretto
lua.execute('lfg.calls = {}; ItemRefTooltip:SetHyperlink("keystone:180653:250:12:0:0:0:0")')
assert row.IsShown(row) and KL.GetCurrent().activityID == 100
assert list(g.lfg.calls.values()) == ["SetEntryTitle:100:10:nil:4"], list(g.lfg.calls.values())  # titolo al click sul link
lua.execute("lfg.calls = {}; psBtn = select(3, KeyLinkLister.GetRow()); psBtn._scripts.OnClick(psBtn)")
assert g.KeyLinkListerDB.playstyle == 1 and list(g.lfg.calls.values()) == ["SetEntryTitle:100:10:nil:1"]  # ciclo 4 -> 1
lua.execute("KeyLinkListerDB.playstyle = 4; KeyLinkLister.RefreshRow()")
assert listBtn.GetText(listBtn) == "List Group", listBtn.GetText(listBtn)
assert listBtn.IsEnabled(listBtn) and psBtn.GetText(psBtn) == "Competitive"
lua.execute('ItemRefTooltip:SetHyperlink("keystone:180653:250:12:0:0:0:0")')   # stesso link = toggle off
assert not row.IsShown(row) and KL.GetCurrent() is None
lua.execute('ItemRefTooltip:SetHyperlink("item:19019:0:0:0")')
assert not row.IsShown(row)
lua.execute('ItemRefTooltip:SetHyperlink("keystone:180653:250:12:0:0:0:0")')
assert row.IsShown(row)
lua.execute("ItemRefTooltip:Hide()")
assert not row.IsShown(row) and KL.GetCurrent() is None

# etichetta "già in lista" disabilita il pulsante; altra activity attiva => "Re-list"
lua.execute('lfg.active = { activityIDs = { 100 } }; ItemRefTooltip:SetHyperlink("keystone:180653:250:12:0:0:0:0")')
assert not listBtn.IsEnabled(listBtn) and listBtn.GetText(listBtn) == "Already listed"
lua.execute("lfg.active = { activityIDs = { 102 } }; KeyLinkLister.RefreshRow()")
assert listBtn.IsEnabled(listBtn) and listBtn.GetText(listBtn) == "Re-list Group"
lua.execute("lfg.active = nil")

# click sul pulsante: crea, poi ACTIVE_ENTRY_UPDATE(createdNew) apre il finder
lua.execute("""
lfg.calls = {}; opened = 0
LFGListUtil_OpenBestWindow = function() opened = opened + 1 end
listBtn = select(2, KeyLinkLister.GetRow())
listBtn._scripts.OnClick(listBtn)
ev._scripts.OnEvent(ev, "LFG_LIST_ACTIVE_ENTRY_UPDATE", true)
""")
assert "CreateListing" in list(g.lfg.calls.values()) and g.opened == 1
lua.execute("now = 5000; ev._scripts.OnEvent(ev, 'LFG_LIST_ACTIVE_ENTRY_UPDATE', true)")
assert g.opened == 1, "evento fuori finestra non deve riaprire il finder"

# relist in due click (RemoveListing e CreateListing sono entrambe hardware-event):
# listing attivo per altro dungeon -> click 1 rimuove, evento -> "List Group", click 2 crea
lua.execute("""
lfg.calls = {}; now = 1000; lfg.active = { activityIDs = { 102 } }
KeyLinkLister.RefreshRow()
listBtn._scripts.OnClick(listBtn)
""")
assert listBtn.GetText(listBtn) == "Re-list Group"
assert list(g.lfg.calls.values()) == ["RemoveListing"], list(g.lfg.calls.values())
lua.execute("lfg.calls = {}; lfg.active = nil; ev._scripts.OnEvent(ev, 'LFG_LIST_ACTIVE_ENTRY_UPDATE', nil)")
assert listBtn.GetText(listBtn) == "List Group"
lua.execute("listBtn._scripts.OnClick(listBtn)")
assert list(g.lfg.calls.values()) == ["CreateListing"], list(g.lfg.calls.values())

# fallimento sincrono: nessun pannello nello stesso click (evento speso); il click dopo apre il pannello PvE
lua.execute("""
lfg.calls = {}; shownStub = nil
C_LFGList.CreateListing = function() lfg.calls[#lfg.calls+1] = "CreateListing"; return false end
PVEFrame_ShowFrame = function(_, stub) shownStub = stub end
listBtn._scripts.OnClick(listBtn)
""")
assert KL.GetCurrent().forcePanel is True and g.shownStub is None
assert listBtn.GetText(listBtn) == "Open panel", listBtn.GetText(listBtn)
assert list(g.lfg.calls.values()) == ["CreateListing", "SetEntryTitle:100:10:nil:4", "CreateListing"], list(g.lfg.calls.values())
lua.execute("listBtn._scripts.OnClick(listBtn)")
assert g.shownStub == "LFGListPVEStub"
lua.execute('C_LFGList.CreateListing = function(d) lfg.calls[#lfg.calls+1] = "CreateListing"; lfg.lastCreate = d; return true end')

# senza key di quel dungeon nel gruppo (authenticator ok): niente titolo al link, il pulsante apre il pannello
# Blizzard prefillato con UN solo Select, titolo suggerito nel campo (o nel placeholder) e focus.
lua.execute("""
lfg.ownedKeystones[100] = nil; lfg.calls = {}; shownStub = nil
group.home = false; group.members = 0            -- da soli: senza key il server rifiuta sempre -> pannello
ec = { Name = CreateFrame("EditBox", "Name") }   -- tabella semplice: i campi assenti (dropdown, Label) devono essere nil
ec.ListGroupButton = CreateFrame("Button", "LGB"); clicks = 0
ec.ListGroupButton.Click = function() clicks = clicks + 1 end
ec.Name.Instructions = CreateFrame("FontString", "Instr"); ec.Name.Instructions._text = "A descriptive title"
ec.Name.SetFocus = function(s) s._focused = true end
LFGListFrame = { baseFilters = 4, EntryCreation = ec, CategorySelection = {} }
selects = 0
LFGListEntryCreation_Clear = function(e) e._cleared = true; e.generalPlaystyle = 0 end
LFGListEntryCreation_Select = function(e, f, c, g, a) selects = selects + 1; e.selectedCategory = c; e.selectedGroup = g; e.selectedActivity = a end
LFGListEntryCreation_UpdateValidState = function(e) e._validated = true end
LFGListFrame_SetActivePanel = function(f, p) f.activePanel = p end
LFGListCategorySelection_SelectCategory = function(cs, c) cs.selectedCategory = c end
C_LFGList.GetLfgCategoryInfo = function() return { name = "Dungeons" } end
ItemRefTooltip:SetHyperlink("keystone:180653:250:12:0:0:0:0")   -- toggle off
ItemRefTooltip:SetHyperlink("keystone:180653:250:12:0:0:0:0")
""")
assert list(g.lfg.calls.values()) == [], list(g.lfg.calls.values())   # nessun SetEntryTitle al link
assert listBtn.GetText(listBtn) == "Open panel" and listBtn.IsEnabled(listBtn)
lua.execute("listBtn._scripts.OnClick(listBtn)")
assert g.shownStub == "LFGListPVEStub" and list(g.lfg.calls.values()) == []
ec = g.ec
assert g.selects == 1 and ec.selectedActivity == 100 and ec.selectedGroup == 10 and ec.selectedCategory == 2
assert ec.generalPlaystyle == 4 and ec.editMode is False and ec.baseFilters == 4 and ec._cleared
assert lua.eval("LFGListFrame.activePanel == ec"), "pannello EntryCreation non attivato"   # identità confrontata lato Lua
assert ec._validated and ec.Name._focused
assert ec.Name._text == "+12", ec.Name._text                        # SetText permesso nello stub => applicato
# Invio nel campo Title = click su List Group (solo se abilitato)
lua.execute("ec.Name._scripts.OnEnterPressed(ec.Name)")
assert g.clicks == 1
lua.execute("ec.ListGroupButton._enabled = false; ec.Name._scripts.OnEnterPressed(ec.Name)")
assert g.clicks == 1
lua.execute("ec.ListGroupButton._enabled = true")
# SetText ignorato (securityDisableSetText): il suggerimento va nel placeholder e in chat
lua.execute("""
ec.Name._text = ""; ec.Name.SetText = function() end; printed = {}
listBtn._scripts.OnClick(listBtn)
""")
assert ec.Name.Instructions._text == "+12" and ec.Name._klOrigInstructions == "A descriptive title"
assert g.selects == 1, "stesso dungeon già selezionato: niente Clear/Select (il titolo digitato deve restare)"
assert any("Suggested title" in p and "+12" in p for p in g.printed.values()), list(g.printed.values())
lua.execute('SlashCmdList.KEYLINKLISTER("title +%d %s")')
assert KL.SuggestedTitle(15) == "+15 Competitive", KL.SuggestedTitle(15)
lua.execute('KeyLinkListerDB.titleFormat = nil')
# senza key propria ma IN GRUPPO (la key può averla un membro): tentativo diretto, non pannello
lua.execute("""
group.home = true; group.leader = true; group.members = 3; lfg.calls = {}; shownStub = nil
ItemRefTooltip:SetHyperlink("keystone:180653:250:12:0:0:0:0")   -- toggle off
ItemRefTooltip:SetHyperlink("keystone:180653:250:12:0:0:0:0")
""")
assert listBtn.GetText(listBtn) == "List Group"
assert list(g.lfg.calls.values()) == ["SetEntryTitle:100:10:nil:4"]      # titolo al link come per key propria
lua.execute("lfg.calls = {}; listBtn._scripts.OnClick(listBtn)")
assert "CreateListing" in list(g.lfg.calls.values()) and g.shownStub is None
lua.execute("lfg.ownedKeystones[100] = 12")

# OnTooltipCleared (contenuto sostituito senza SetHyperlink) nasconde la riga
lua.execute('ItemRefTooltip:SetHyperlink("keystone:180653:250:12:0:0:0:0")')   # toggle off
lua.execute('ItemRefTooltip:SetHyperlink("keystone:180653:250:12:0:0:0:0")')
assert row.IsShown(row) and KL.GetCurrent().forcePanel is None
lua.execute("ItemRefTooltip._scripts.OnTooltipCleared(ItemRefTooltip)")
assert not row.IsShown(row) and KL.GetCurrent() is None

# log diagnostico persistente in SavedVariables
loglines = list(g.KeyLinkListerDB.log.values())
assert any(l.startswith("00:00:00 LINK ") for l in loglines) and any(" CLICK " in l for l in loglines), loglines[:3]
assert any("CreateListing #1 -> false" in l for l in loglines)
lua.execute('SlashCmdList.KEYLINKLISTER("log 3")')
assert any("log lines" in p for p in g.printed.values())

# ---- slash --------------------------------------------------------------------
lua.execute('SlashCmdList.KEYLINKLISTER("playstyle 2")')
assert g.KeyLinkListerDB.playstyle == 2
lua.execute('SlashCmdList.KEYLINKLISTER("mode panel")')
assert g.KeyLinkListerDB.mode == "panel"
lua.execute('SlashCmdList.KEYLINKLISTER("score 2500")')
assert g.KeyLinkListerDB.minScore == 2500
lua.execute('SlashCmdList.KEYLINKLISTER("xfaction")')
assert g.KeyLinkListerDB.crossFaction is False

print("test_keylinklister: OK")
