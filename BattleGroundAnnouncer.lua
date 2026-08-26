-- BattlegroundAnnouncer.lua
-- Combines the Arathi Basin node caller and the Warsong Gulch caller into
-- one addon. Both panels auto show/hide based on zone, same as before.
--
-- Slash commands are now routed through a single /bga prefix:
--   /bga ab <lock|unlock|scale|show|hide|auto|reset>
--   /bga wsg <lock|unlock|scale|show|hide|auto|reset>

-- Must match the addon's actual folder / .toc name exactly (ADDON_LOADED's
-- arg1 comparison is case-sensitive) - see BattleGroundAnnouncer.toc.
local ADDON_NAME = "BattleGroundAnnouncer"

BGADB = BGADB or {}
BGADB.ab = BGADB.ab or {}
BGADB.wsg = BGADB.wsg or {}

----------------------------------------------------------------------
-- Shared helper
----------------------------------------------------------------------
local function SendBGMessage(msg)
    if IsInInstance and select(2, IsInInstance()) == "pvp" then
        SendChatMessage(msg, "BATTLEGROUND")
    else
        -- Fallback so testing outside a BG doesn't error out
        SendChatMessage(msg, "SAY")
    end
end

-- Forward declarations so the shared event handler and the slash
-- dispatcher can reach into each module.
local AB_OnAddonLoaded, AB_OnZoneChanged, AB_HandleSlash
local WSG_OnAddonLoaded, WSG_OnZoneChanged, WSG_HandleSlash

----------------------------------------------------------------------
-- ARATHI BASIN MODULE
----------------------------------------------------------------------
do
    local ZONE_NAME = "Arathi Basin"
    local DB = BGADB.ab

    -- Node definitions: id, display name, chat callout text
    -- Ordered clockwise starting at the top, roughly matching the AB map layout.
    local NODES = {
        { id = "GM", name = "Gold Mine",    callout = "Gold Mine" },
        { id = "BS", name = "Blacksmith",   callout = "Blacksmith" },
        { id = "F",  name = "Farm",         callout = "Farm" },
        { id = "ST", name = "Stables",      callout = "Stables" },
        { id = "LM", name = "Lumber Mill",  callout = "Lumber Mill" },
    }

    local NUMBERS = { "1", "2", "3", "4", "5" }

    local function EnsureDB()
        DB.point = DB.point or "CENTER"
        DB.relPoint = DB.relPoint or "CENTER"
        DB.x = DB.x or 0
        DB.y = DB.y or 150
        DB.scale = DB.scale or 1.0
        if DB.locked == nil then
            DB.locked = false
        end
    end

    local mainFrame = CreateFrame("Frame", "BGA_AB_Frame", UIParent)
    mainFrame:SetSize(240, 240)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetClampedToScreen(true)
    mainFrame:Hide()

    local function SavePosition()
        local point, _, relPoint, x, y = mainFrame:GetPoint()
        DB.point = point
        DB.relPoint = relPoint
        DB.x = x
        DB.y = y
    end

    local function ApplyPosition()
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(DB.point, UIParent, DB.relPoint, DB.x, DB.y)
    end

    local MIN_SCALE = 0.5
    local MAX_SCALE = 2.0

    local UpdateLockVisual

    local function ApplyScale()
        mainFrame:SetScale(DB.scale)
    end

    local function SetScale(newScale)
        if newScale < MIN_SCALE then newScale = MIN_SCALE end
        if newScale > MAX_SCALE then newScale = MAX_SCALE end
        DB.scale = newScale
        ApplyScale()
        if UpdateLockVisual then UpdateLockVisual() end
    end

    -- Hold Ctrl and scroll to resize; hold Shift and drag to move. This
    -- works regardless of /bga ab lock state - no need to lock/unlock at
    -- all for everyday adjustments; holding the modifier key is enough.
    mainFrame:EnableMouseWheel(true)
    mainFrame:SetScript("OnMouseWheel", function(self, delta)
        if not IsControlKeyDown() then return end
        SetScale(DB.scale + delta * 0.1)
    end)

    mainFrame:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    local titleBar = CreateFrame("Frame", nil, mainFrame)
    titleBar:SetSize(120, 20)
    titleBar:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:SetScript("OnMouseDown", function()
        if IsShiftKeyDown() then
            mainFrame:StartMoving()
        end
    end)
    titleBar:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        SavePosition()
    end)
    titleBar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("AB Caller")
        GameTooltip:AddLine("Hold shift and drag to move wheel.", 1, 1, 1)
        GameTooltip:AddLine("Hold ctrl and scroll mousewheel to change size.", 1, 1, 1)
        GameTooltip:Show()
    end)
    titleBar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    titleText:SetText("AB Caller")

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints(titleBar)
    titleBg:SetTexture(0, 0, 0, 0.4)

    local ShowNodeWheel, ShowNumberWheel

    local resetOverlay = CreateFrame("Button", "BGA_AB_ResetOverlay", UIParent)
    -- BACKGROUND is the lowest strata: it still catches clicks on bare
    -- screen space (to back out of the submenu) but never outranks real
    -- UI - action bars, minimap, other addons - so it can't swallow
    -- clicks meant for them the way FULLSCREEN did (mainFrame itself
    -- stays on top either way, since it's FULLSCREEN_DIALOG below).
    resetOverlay:SetFrameStrata("BACKGROUND")
    resetOverlay:SetAllPoints(UIParent)
    resetOverlay:EnableMouse(true)
    resetOverlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    resetOverlay:Hide()
    resetOverlay:SetScript("OnClick", function()
        ShowNodeWheel()
    end)

    mainFrame:SetFrameStrata("FULLSCREEN_DIALOG")

    local radius = 95
    local nodeAngleStep = (2 * math.pi) / #NODES
    local numberAngleStep = (2 * math.pi) / #NUMBERS

    local nodeButtons = {}
    local numberButtons = {}
    local selectedNode = nil

    for i, node in ipairs(NODES) do
        local angle = -math.pi / 2 + (i - 1) * nodeAngleStep
        local x = radius * math.cos(angle)
        local y = radius * math.sin(angle)

        local btn = CreateFrame("Button", "BGA_AB_NodeButton" .. node.id, mainFrame, "UIPanelButtonTemplate")
        btn:SetSize(96, 26)
        btn:SetPoint("CENTER", mainFrame, "CENTER", x, y)
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetText(node.name)
        btn.node = node

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(node.name)
            GameTooltip:AddLine("Click to choose how many are incoming", 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        btn:SetScript("OnClick", function(self)
            ShowNumberWheel(self.node)
        end)

        nodeButtons[i] = btn
    end

    for i, num in ipairs(NUMBERS) do
        local angle = math.pi / 2 - (i - 1) * numberAngleStep
        local x = radius * math.cos(angle)
        local y = radius * math.sin(angle)

        local btn = CreateFrame("Button", "BGA_AB_NumberButton" .. num, mainFrame, "UIPanelButtonTemplate")
        btn:SetSize(96, 26)
        btn:SetPoint("CENTER", mainFrame, "CENTER", x, y)
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetText(num)
        btn:Hide()

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if selectedNode then
                GameTooltip:AddLine(selectedNode.callout .. ": " .. num .. " Incoming")
            else
                GameTooltip:AddLine(num .. " incoming")
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        btn:SetScript("OnClick", function()
            if selectedNode then
                local msg = selectedNode.callout .. ": " .. num .. " Incoming"
                SendBGMessage(msg)
            end
            ShowNodeWheel()
        end)

        numberButtons[i] = btn
    end

    ShowNodeWheel = function()
        selectedNode = nil
        for _, b in ipairs(numberButtons) do b:Hide() end
        for _, b in ipairs(nodeButtons) do b:Show() end
        resetOverlay:Hide()
    end

    ShowNumberWheel = function(node)
        selectedNode = node
        for _, b in ipairs(nodeButtons) do b:Hide() end
        for _, b in ipairs(numberButtons) do b:Show() end
        resetOverlay:Show()
    end

    for _, b in ipairs(numberButtons) do b:Hide() end

    local function UpdateLockVisual_impl()
        local pct = math.floor(DB.scale * 100 + 0.5) .. "%"
        if DB.locked then
            titleText:SetText("AB Caller (locked)")
        else
            titleText:SetText("AB Caller " .. pct)
        end
    end
    UpdateLockVisual = UpdateLockVisual_impl

    local function SetLocked(locked)
        DB.locked = locked
        UpdateLockVisual()
    end

    local manualOverride = nil

    local function UpdateVisibility()
        local shouldShow

        if manualOverride == true then
            shouldShow = true
        elseif manualOverride == false then
            shouldShow = false
        else
            local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
            shouldShow = (zone == ZONE_NAME)
        end

        if shouldShow then
            mainFrame:Show()
        else
            mainFrame:Hide()
            ShowNodeWheel()
        end
    end

    AB_OnAddonLoaded = function()
        -- Re-point DB at the real loaded table now that SavedVariables
        -- have actually been read from disk (they load AFTER this file's
        -- own top-level code runs, so the DB captured earlier at file-load
        -- time was a disconnected placeholder, not the persisted data).
        DB = BGADB.ab
        EnsureDB()
        ApplyPosition()
        ApplyScale()
        UpdateLockVisual()
        UpdateVisibility()
    end

    AB_OnZoneChanged = function()
        UpdateVisibility()
    end

    AB_HandleSlash = function(msg)
        msg = (msg or ""):lower():match("^%s*(.-)%s*$")

        if msg == "lock" then
            SetLocked(true)
            print("|cff33ff99Battleground Announcer [AB]|r: marked locked. (Shift-drag / Ctrl-scroll still work anytime.)")
        elseif msg == "unlock" then
            SetLocked(false)
            print("|cff33ff99Battleground Announcer [AB]|r: marked unlocked. Hold shift and drag, or hold ctrl and scroll, anytime.")
        elseif msg == "show" then
            manualOverride = true
            UpdateVisibility()
            print("|cff33ff99Battleground Announcer [AB]|r: shown (manual override). Type /bga ab auto to return to zone-based show/hide.")
        elseif msg == "hide" then
            manualOverride = false
            UpdateVisibility()
            print("|cff33ff99Battleground Announcer [AB]|r: hidden (manual override). Type /bga ab auto to return to zone-based show/hide.")
        elseif msg == "auto" then
            manualOverride = nil
            UpdateVisibility()
            print("|cff33ff99Battleground Announcer [AB]|r: back to auto show/hide based on zone.")
        elseif msg == "reset" then
            DB.point = "CENTER"
            DB.relPoint = "CENTER"
            DB.x = 0
            DB.y = 150
            ApplyPosition()
            SetScale(1.0)
            print("|cff33ff99Battleground Announcer [AB]|r: position and size reset.")
        elseif msg:match("^scale") then
            local value = tonumber(msg:match("^scale%s+(.+)$"))
            if value then
                SetScale(value)
                print("|cff33ff99Battleground Announcer [AB]|r: scale set to " .. math.floor(DB.scale * 100 + 0.5) .. "%.")
            else
                print("|cff33ff99Battleground Announcer [AB]|r: usage /bga ab scale <" .. MIN_SCALE .. "-" .. MAX_SCALE .. ">")
            end
        else
            print("|cff33ff99Battleground Announcer [AB]|r commands:")
            print("  /bga ab lock - mark as locked (cosmetic; shift-drag/ctrl-scroll still work)")
            print("  /bga ab unlock - mark as unlocked")
            print("  /bga ab scale <0.5-2.0> - set size precisely")
            print("  /bga ab show - force show")
            print("  /bga ab hide - force hide")
            print("  /bga ab auto - resume auto show/hide in Arathi Basin")
            print("  /bga ab reset - reset frame position and size")
        end
    end
end

----------------------------------------------------------------------
-- WARSONG GULCH MODULE
----------------------------------------------------------------------
do
    local ZONE_NAME = "Warsong Gulch"
    local DB = BGADB.wsg

    -- Location spots: id, display name, chat callout text, spatial position
    -- (x, y offsets from the frame's TOP anchor point), button width, and
    -- which menus (offense / defense) show this spot.
    --
    -- Row layout (top to bottom): Offense/Defense, then the status label,
    -- then Tunnel+Ramp side by side (shared by both menus), then
    -- GraveYard+Flag Room side by side (Offense only), then Roof centered
    -- (Offense only).
    local LOCATIONS = {
        { id = "TUNNEL", name = "Tunnel",     callout = "Tunnel",    x = -60,  y = -70,  w = 100, offense = true,  defense = true  },
        { id = "RAMP",   name = "Ramp",       callout = "Ramp",      x = 60,   y = -70,  w = 100, offense = true,  defense = true  },
        { id = "GY",     name = "GraveYard",  callout = "GraveYard", x = -90,  y = -150, w = 110, offense = true,  defense = false },
        { id = "FR",     name = "Flag Room",  callout = "Flag Room", x = 90,   y = -150, w = 110, offense = true,  defense = false },
        { id = "ROOF",   name = "Roof",       callout = "Roof",      x = 0,    y = -190, w = 100, offense = true,  defense = false },
    }

    local function EnsureDB()
        DB.point = DB.point or "CENTER"
        DB.relPoint = DB.relPoint or "CENTER"
        DB.x = DB.x or 0
        DB.y = DB.y or -150
        DB.scale = DB.scale or 1.0
        if DB.locked == nil then
            DB.locked = false
        end
    end

    local FRAME_WIDTH = 320
    local FRAME_HEIGHT = 240

    local mainFrame = CreateFrame("Frame", "BGA_WSG_Frame", UIParent)
    mainFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetClampedToScreen(true)
    mainFrame:Hide()

    local function SavePosition()
        local point, _, relPoint, x, y = mainFrame:GetPoint()
        DB.point = point
        DB.relPoint = relPoint
        DB.x = x
        DB.y = y
    end

    local function ApplyPosition()
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(DB.point, UIParent, DB.relPoint, DB.x, DB.y)
    end

    local MIN_SCALE = 0.5
    local MAX_SCALE = 2.0

    local UpdateLockVisual

    local function ApplyScale()
        mainFrame:SetScale(DB.scale)
    end

    local function SetScale(newScale)
        if newScale < MIN_SCALE then newScale = MIN_SCALE end
        if newScale > MAX_SCALE then newScale = MAX_SCALE end
        DB.scale = newScale
        ApplyScale()
        if UpdateLockVisual then UpdateLockVisual() end
    end

    -- Hold Ctrl and scroll to resize; hold Shift and drag to move. This
    -- works regardless of /bga wsg lock state - no need to lock/unlock at
    -- all for everyday adjustments; holding the modifier key is enough.
    mainFrame:EnableMouseWheel(true)
    mainFrame:SetScript("OnMouseWheel", function(self, delta)
        if not IsControlKeyDown() then return end
        SetScale(DB.scale + delta * 0.1)
    end)

    mainFrame:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    -- Status label position: sits close below Offense/Defense on the main
    -- menu, and drops down to sit close below Tunnel/Ramp once a submenu
    -- (Offense or Defense) is open - same tight gap in both cases.
    local LABEL_Y_MAIN = -58
    local LABEL_Y_SUBMENU = -110

    local titleBar = CreateFrame("Frame", nil, mainFrame)
    titleBar:SetSize(150, 20)
    titleBar:SetPoint("TOP", mainFrame, "TOP", 0, LABEL_Y_MAIN)
    titleBar:EnableMouse(true)
    titleBar:SetScript("OnMouseDown", function()
        if IsShiftKeyDown() then
            mainFrame:StartMoving()
        end
    end)
    titleBar:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        SavePosition()
    end)
    titleBar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("WSG Caller")
        GameTooltip:AddLine("Hold shift and drag to move wheel.", 1, 1, 1)
        GameTooltip:AddLine("Hold ctrl and scroll mousewheel to change size.", 1, 1, 1)
        GameTooltip:Show()
    end)
    titleBar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    titleText:SetText("WSG Caller")

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints(titleBar)
    titleBg:SetTexture(0, 0, 0, 0.4)

    local ShowMainMenu, ShowOffenseMenu, ShowDefenseMenu

    local resetOverlay = CreateFrame("Button", "BGA_WSG_ResetOverlay", UIParent)
    -- BACKGROUND is the lowest strata: it still catches clicks on bare
    -- screen space (to back out of the submenu) but never outranks real
    -- UI - action bars, minimap, other addons - so it can't swallow
    -- clicks meant for them the way FULLSCREEN did (mainFrame itself
    -- stays on top either way, since it's FULLSCREEN_DIALOG below).
    resetOverlay:SetFrameStrata("BACKGROUND")
    resetOverlay:SetAllPoints(UIParent)
    resetOverlay:EnableMouse(true)
    resetOverlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    resetOverlay:Hide()
    resetOverlay:SetScript("OnClick", function()
        ShowMainMenu()
    end)

    mainFrame:SetFrameStrata("FULLSCREEN_DIALOG")

    local BUTTON_HEIGHT = 26

    local offenseMainBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    offenseMainBtn:SetSize(100, BUTTON_HEIGHT)
    offenseMainBtn:SetPoint("TOP", mainFrame, "TOP", -70, -18)
    offenseMainBtn:RegisterForClicks("LeftButtonUp")
    offenseMainBtn:SetText("Offense")
    offenseMainBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Offense")
        GameTooltip:AddLine("Call out the flag's location", 1, 1, 1)
        GameTooltip:Show()
    end)
    offenseMainBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    offenseMainBtn:SetScript("OnClick", function() ShowOffenseMenu() end)

    local defenseMainBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    defenseMainBtn:SetSize(100, BUTTON_HEIGHT)
    defenseMainBtn:SetPoint("TOP", mainFrame, "TOP", 70, -18)
    defenseMainBtn:RegisterForClicks("LeftButtonUp")
    defenseMainBtn:SetText("Defense")
    defenseMainBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Defense")
        GameTooltip:AddLine("Call out an incoming enemy", 1, 1, 1)
        GameTooltip:Show()
    end)
    defenseMainBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    defenseMainBtn:SetScript("OnClick", function() ShowDefenseMenu() end)

    local mainMenuButtons = { offenseMainBtn, defenseMainBtn }

    local currentMode = nil
    local locationButtons = {}

    for i, spot in ipairs(LOCATIONS) do
        local btn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
        btn:SetSize(spot.w, BUTTON_HEIGHT)
        btn:SetPoint("TOP", mainFrame, "TOP", spot.x, spot.y)
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetText(spot.name)
        btn:Hide()

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if currentMode == "defense" then
                GameTooltip:AddLine("Incoming: " .. spot.callout)
            else
                GameTooltip:AddLine("Flag Carrier @ " .. spot.callout)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        btn:SetScript("OnClick", function()
            if currentMode == "defense" then
                SendBGMessage("Incoming: " .. spot.callout)
            else
                SendBGMessage("Flag Carrier @ " .. spot.callout)
            end
            ShowMainMenu()
        end)

        spot.button = btn
        locationButtons[i] = btn
    end

    local function SetLabelPosition(y)
        titleBar:ClearAllPoints()
        titleBar:SetPoint("TOP", mainFrame, "TOP", 0, y)
    end

    ShowMainMenu = function()
        currentMode = nil
        for _, b in ipairs(locationButtons) do b:Hide() end
        for _, b in ipairs(mainMenuButtons) do b:Show() end
        SetLabelPosition(LABEL_Y_MAIN)
        resetOverlay:Hide()
    end

    ShowOffenseMenu = function()
        currentMode = "offense"
        for _, b in ipairs(mainMenuButtons) do b:Hide() end
        for _, spot in ipairs(LOCATIONS) do
            if spot.offense then spot.button:Show() else spot.button:Hide() end
        end
        SetLabelPosition(LABEL_Y_SUBMENU)
        resetOverlay:Show()
    end

    ShowDefenseMenu = function()
        currentMode = "defense"
        for _, b in ipairs(mainMenuButtons) do b:Hide() end
        for _, spot in ipairs(LOCATIONS) do
            if spot.defense then spot.button:Show() else spot.button:Hide() end
        end
        SetLabelPosition(LABEL_Y_SUBMENU)
        resetOverlay:Show()
    end

    for _, b in ipairs(locationButtons) do b:Hide() end

    local function UpdateLockVisual_impl()
        local pct = math.floor(DB.scale * 100 + 0.5) .. "%"
        if DB.locked then
            titleText:SetText("WSG Caller (locked)")
        else
            titleText:SetText("WSG Caller " .. pct)
        end
    end
    UpdateLockVisual = UpdateLockVisual_impl

    local function SetLocked(locked)
        DB.locked = locked
        UpdateLockVisual()
    end

    local manualOverride = nil

    local function UpdateVisibility()
        local shouldShow

        if manualOverride == true then
            shouldShow = true
        elseif manualOverride == false then
            shouldShow = false
        else
            local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
            shouldShow = (zone == ZONE_NAME)
        end

        if shouldShow then
            mainFrame:Show()
        else
            mainFrame:Hide()
            ShowMainMenu()
        end
    end

    WSG_OnAddonLoaded = function()
        -- Re-point DB at the real loaded table now that SavedVariables
        -- have actually been read from disk (see comment in the AB
        -- module's AB_OnAddonLoaded for why this is necessary).
        DB = BGADB.wsg
        EnsureDB()
        ApplyPosition()
        ApplyScale()
        UpdateLockVisual()
        UpdateVisibility()
    end

    WSG_OnZoneChanged = function()
        UpdateVisibility()
    end

    WSG_HandleSlash = function(msg)
        msg = (msg or ""):lower():match("^%s*(.-)%s*$")

        if msg == "lock" then
            SetLocked(true)
            print("|cff33ff99Battleground Announcer [WSG]|r: marked locked. (Shift-drag / Ctrl-scroll still work anytime.)")
        elseif msg == "unlock" then
            SetLocked(false)
            print("|cff33ff99Battleground Announcer [WSG]|r: marked unlocked. Hold shift and drag, or hold ctrl and scroll, anytime.")
        elseif msg == "show" then
            manualOverride = true
            UpdateVisibility()
            print("|cff33ff99Battleground Announcer [WSG]|r: shown (manual override). Type /bga wsg auto to return to zone-based show/hide.")
        elseif msg == "hide" then
            manualOverride = false
            UpdateVisibility()
            print("|cff33ff99Battleground Announcer [WSG]|r: hidden (manual override). Type /bga wsg auto to return to zone-based show/hide.")
        elseif msg == "auto" then
            manualOverride = nil
            UpdateVisibility()
            print("|cff33ff99Battleground Announcer [WSG]|r: back to auto show/hide based on zone.")
        elseif msg == "reset" then
            DB.point = "CENTER"
            DB.relPoint = "CENTER"
            DB.x = 0
            DB.y = -150
            ApplyPosition()
            SetScale(1.0)
            print("|cff33ff99Battleground Announcer [WSG]|r: position and size reset.")
        elseif msg:match("^scale") then
            local value = tonumber(msg:match("^scale%s+(.+)$"))
            if value then
                SetScale(value)
                print("|cff33ff99Battleground Announcer [WSG]|r: scale set to " .. math.floor(DB.scale * 100 + 0.5) .. "%.")
            else
                print("|cff33ff99Battleground Announcer [WSG]|r: usage /bga wsg scale <" .. MIN_SCALE .. "-" .. MAX_SCALE .. ">")
            end
        else
            print("|cff33ff99Battleground Announcer [WSG]|r commands:")
            print("  /bga wsg lock - mark as locked (cosmetic; shift-drag/ctrl-scroll still work)")
            print("  /bga wsg unlock - mark as unlocked")
            print("  /bga wsg scale <0.5-2.0> - set size precisely")
            print("  /bga wsg show - force show")
            print("  /bga wsg hide - force hide")
            print("  /bga wsg auto - resume auto show/hide in Warsong Gulch")
            print("  /bga wsg reset - reset frame position and size")
        end
    end
end

----------------------------------------------------------------------
-- Shared events
----------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        AB_OnAddonLoaded()
        WSG_OnAddonLoaded()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        AB_OnZoneChanged()
        WSG_OnZoneChanged()
    end
end)

----------------------------------------------------------------------
-- Slash command dispatcher: /bga ab ...  and  /bga wsg ...
----------------------------------------------------------------------
SLASH_BGANNOUNCER1 = "/bga"
SlashCmdList["BGANNOUNCER"] = function(msg)
    msg = msg or ""
    local sub, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    sub = (sub or ""):lower()

    if sub == "ab" then
        AB_HandleSlash(rest)
    elseif sub == "wsg" then
        WSG_HandleSlash(rest)
    else
        print("|cff33ff99Battleground Announcer|r commands:")
        print("  /bga ab <command> - control the Arathi Basin caller")
        print("  /bga wsg <command> - control the Warsong Gulch caller")
        print("  where <command> is: lock, unlock, scale <0.5-2.0>, show, hide, auto, reset")
        print("  Examples: /bga ab lock   /bga wsg scale 1.2")
    end
end
