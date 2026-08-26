-- Regression tests for BattleGroundAnnouncer.lua, run against a minimal
-- WoW 3.3.0a API mock (wow_mock.lua) so they can run outside the game
-- client. Run with: lua5.1 tests/test_bga.lua
--
-- Covers two real bugs reported against v2.1.3:
--
-- 1. The AB/WSG frames never showed up automatically in the battleground
--    (only a manual show -> unlock -> reset -> hide -> auto sequence made
--    them appear). Root cause: ADDON_NAME ("BattlegroundAnnouncer") did
--    not match the addon's actual folder/.toc name ("BattleGroundAnnouncer"
--    - capital G), so the ADDON_LOADED handler's case-sensitive arg1 check
--    never matched. AB_OnAddonLoaded/WSG_OnAddonLoaded (which seed DB
--    defaults and anchor the frame via ApplyPosition) never ran, so the
--    frame was "shown" (zone-change events still fire) but never anchored,
--    and any command touching DB.scale (e.g. /bga wsg unlock) crashed
--    silently because EnsureDB() never seeded it.
--
-- 2. Moving the WSG panel near the toolbar made toolbar buttons
--    unclickable. Root cause: resetOverlay (the invisible "click anywhere
--    to back out of a submenu" catcher) covered the entire screen
--    (SetAllPoints(UIParent)) at FULLSCREEN strata, which outranks normal
--    game UI like action bars, so while a submenu was open it intercepted
--    every click on screen, not just clicks on the panel.

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("PASS: " .. name)
    else
        failures = failures + 1
        print("FAIL: " .. name .. (detail and (" - " .. detail) or ""))
    end
end

local function freshEnv(luaPath)
    -- Each scenario needs a clean mock + freshly loaded addon (the addon
    -- has file-level state, e.g. module DB references, so it can't be
    -- reloaded into the same Lua state twice).
    dofile("tests/wow_mock.lua")
    dofile(luaPath)
end

local ADDON_PATH = arg[1] or "./BattleGroundAnnouncer.lua"
local REAL_FOLDER_NAME = "BattleGroundAnnouncer" -- matches the .toc filename

----------------------------------------------------------------------
-- Bug 1: frame shows up and is anchored after entering the zone,
-- without needing any manual slash commands.
----------------------------------------------------------------------
do
    freshEnv(ADDON_PATH)
    local wsg = _TEST.frames["BGA_WSG_Frame"]
    local ab = _TEST.frames["BGA_AB_Frame"]

    _TEST.fireEventBroadcast("ADDON_LOADED", REAL_FOLDER_NAME)
    _TEST.setZone("Warsong Gulch")
    _TEST.setInInstance(true, "pvp")
    _TEST.fireEventBroadcast("PLAYER_ENTERING_WORLD")

    check("WSG frame is shown on entering Warsong Gulch", wsg:IsShown())
    check("WSG frame is anchored on entering Warsong Gulch (was nil pre-fix)",
        wsg:GetPoint() ~= nil)
    check("AB frame stays hidden outside Arathi Basin", not ab:IsShown())
end

----------------------------------------------------------------------
-- Bug 1 (companion symptom): DB defaults are seeded before any slash
-- command runs, so /bga wsg unlock doesn't crash on a nil DB.scale.
----------------------------------------------------------------------
do
    freshEnv(ADDON_PATH)
    _TEST.fireEventBroadcast("ADDON_LOADED", REAL_FOLDER_NAME)
    _TEST.setZone("Warsong Gulch")
    _TEST.fireEventBroadcast("PLAYER_ENTERING_WORLD")

    local run = SlashCmdList["BGANNOUNCER"]
    local ok, err = pcall(run, "wsg unlock")
    check("/bga wsg unlock does not error on a fresh install", ok, err)
end

----------------------------------------------------------------------
-- Bug 2: the submenu's full-screen "click to back out" catcher must not
-- run at a strata that outranks normal game UI (action bars etc).
----------------------------------------------------------------------
local HIGH_STRATA = { FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }

do
    freshEnv(ADDON_PATH)
    _TEST.fireEventBroadcast("ADDON_LOADED", REAL_FOLDER_NAME)
    _TEST.setZone("Warsong Gulch")
    _TEST.fireEventBroadcast("PLAYER_ENTERING_WORLD")

    -- Open the Offense submenu by clicking the button with that label.
    local offenseBtn
    for _, f in ipairs(_TEST.allFrames) do
        if f:GetText() == "Offense" then offenseBtn = f end
    end
    check("found the WSG Offense button", offenseBtn ~= nil)
    offenseBtn:GetScript("OnClick")(offenseBtn)

    local overlay = _TEST.frames["BGA_WSG_ResetOverlay"]
    check("WSG resetOverlay strata does not outrank normal game UI",
        not HIGH_STRATA[overlay:GetFrameStrata() or ""],
        "strata=" .. tostring(overlay:GetFrameStrata()))
end

do
    freshEnv(ADDON_PATH)
    _TEST.fireEventBroadcast("ADDON_LOADED", REAL_FOLDER_NAME)
    _TEST.setZone("Arathi Basin")
    _TEST.fireEventBroadcast("PLAYER_ENTERING_WORLD")

    -- Open the AB number wheel by clicking any node button.
    local nodeBtn
    for _, f in ipairs(_TEST.allFrames) do
        if f._name and f._name:match("^BGA_AB_NodeButton") then nodeBtn = f end
    end
    check("found an AB node button", nodeBtn ~= nil)
    nodeBtn:GetScript("OnClick")(nodeBtn)

    local overlay = _TEST.frames["BGA_AB_ResetOverlay"]
    check("AB resetOverlay strata does not outrank normal game UI",
        not HIGH_STRATA[overlay:GetFrameStrata() or ""],
        "strata=" .. tostring(overlay:GetFrameStrata()))
end

----------------------------------------------------------------------
if failures > 0 then
    print(("\n%d check(s) FAILED"):format(failures))
    os.exit(1)
else
    print("\nAll checks passed")
    os.exit(0)
end
