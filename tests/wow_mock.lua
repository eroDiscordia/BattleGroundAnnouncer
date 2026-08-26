-- Minimal WoW 3.3.0a API mock, just enough surface for BattleGroundAnnouncer.lua
-- to load and run its event/slash-command logic outside the game client.

local frames = {}
local allFrames = {}

local FrameMT = {}
FrameMT.__index = FrameMT

function FrameMT:SetSize() end
function FrameMT:SetMovable() end
function FrameMT:EnableMouse() end
function FrameMT:RegisterForDrag() end
function FrameMT:SetClampedToScreen() end
function FrameMT:SetFrameStrata(s) self._strata = s end
function FrameMT:GetFrameStrata() return self._strata end
function FrameMT:EnableMouseWheel() end
function FrameMT:RegisterForClicks() end
function FrameMT:SetText(t) self._text = t end
function FrameMT:GetText() return self._text end
function FrameMT:SetAllPoints() self._point = { "ALL", nil, "ALL", 0, 0 } end
function FrameMT:SetTexture() end
function FrameMT:StartMoving() end
function FrameMT:StopMovingOrSizing() end

function FrameMT:Hide() self._shown = false end
function FrameMT:Show() self._shown = true end
function FrameMT:IsShown() return self._shown == true end

function FrameMT:ClearAllPoints() self._point = nil end
function FrameMT:SetPoint(point, relTo, relPoint, x, y)
    self._point = { point, relTo, relPoint, x, y }
end
function FrameMT:GetPoint()
    if not self._point then return nil end
    return self._point[1], self._point[2], self._point[3], self._point[4], self._point[5]
end

function FrameMT:SetScale(s) self._scale = s end
function FrameMT:GetScale() return self._scale end

function FrameMT:SetScript(name, fn) self._scripts = self._scripts or {}; self._scripts[name] = fn end
function FrameMT:GetScript(name) return self._scripts and self._scripts[name] end

function FrameMT:RegisterEvent(evt) self._events = self._events or {}; self._events[evt] = true end
function FrameMT:CreateFontString() return CreateFrame("FontString") end
function FrameMT:CreateTexture() return CreateFrame("Texture") end
function FrameMT:AddLine() end
function FrameMT:SetOwner() end

function CreateFrame(kind, name, parent, template)
    local f = setmetatable({ _kind = kind, _name = name, _parent = parent, _shown = true }, FrameMT)
    if name then frames[name] = f end
    table.insert(allFrames, f)
    return f
end

UIParent = CreateFrame("Frame", "UIParent")
GameTooltip = CreateFrame("Frame", "GameTooltip")

-- Zone / instance state the test controls
local _zone = "Stormwind City"
local _inInstance, _instanceType = false, nil
function GetRealZoneText() return _zone end
function GetZoneText() return _zone end
function IsInInstance() return _inInstance, _instanceType end

local sentMessages = {}
function SendChatMessage(msg, channel) table.insert(sentMessages, { msg = msg, channel = channel }) end

function IsControlKeyDown() return false end
function IsShiftKeyDown() return false end

SlashCmdList = {}

-- Test control surface
_TEST = {
    frames = frames,
    allFrames = allFrames,
    sentMessages = sentMessages,
    setZone = function(z) _zone = z end,
    setInInstance = function(v, t) _inInstance, _instanceType = v, t end,
    fireEvent = function(frame, event, arg1)
        local handler = frame:GetScript("OnEvent")
        if handler then handler(frame, event, arg1) end
    end,
    -- Fire an event on every frame that registered for it (mimics the
    -- game's event dispatch, since the addon's event frame is anonymous).
    fireEventBroadcast = function(event, arg1)
        for _, f in ipairs(allFrames) do
            if f._events and f._events[event] then
                local handler = f:GetScript("OnEvent")
                if handler then handler(f, event, arg1) end
            end
        end
    end,
}
