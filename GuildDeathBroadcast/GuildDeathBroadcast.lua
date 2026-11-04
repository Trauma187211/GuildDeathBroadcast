local ADDON_PREFIX = "GDB_DEATH_SYNC"
C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)

----------------------------------------------------
-- 1. Create Main Window Frame (Details-style aesthetic)
----------------------------------------------------
local mainFrame = CreateFrame("Frame", "GuildDeathTrackerFrame", UIParent, "BackdropTemplate")
mainFrame:SetSize(320, 180)
mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
mainFrame:SetMovable(true)
mainFrame:SetResizable(true)
mainFrame:SetClampedToScreen(true)
mainFrame:SetResizeBounds(200, 100, 600, 500)
mainFrame:EnableMouse(true)

-- Dark background with thin border
mainFrame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
mainFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
mainFrame:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.8)

----------------------------------------------------
-- 2. Title Header & Drag Bar
----------------------------------------------------
local header = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
header:SetHeight(20)
header:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 3, -3)
header:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -3, -3)
header:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
header:SetBackdropColor(0.12, 0.12, 0.12, 0.95)

header:EnableMouse(true)
header:RegisterForDrag("LeftButton")
header:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
header:SetScript("OnDragStop", function() mainFrame:StopMovingOrSizing() end)

local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
titleText:SetPoint("LEFT", header, "LEFT", 8, 0)
titleText:SetText("|cffFF4500Guild Deaths|r")
titleText:SetTextColor(0.9, 0.9, 0.9)

----------------------------------------------------
-- 3. Resize Handle (Bottom-Right Corner)
----------------------------------------------------
local resizeBtn = CreateFrame("Button", nil, mainFrame)
resizeBtn:SetSize(16, 16)
resizeBtn:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -2, 2)
resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

resizeBtn:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        mainFrame:StartSizing("BOTTOMRIGHT")
    end
end)
resizeBtn:SetScript("OnMouseUp", function()
    mainFrame:StopMovingOrSizing()
end)

----------------------------------------------------
-- 4. Scrollable Log Area
----------------------------------------------------
local scrollFrame = CreateFrame("ScrollFrame", "GuildDeathTrackerScroll", mainFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 5, -5)
scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -26, 5)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(scrollFrame:GetWidth(), 1)
scrollFrame:SetScrollChild(content)

-- Auto-adjust internal width on frame resize
mainFrame:SetScript("OnSizeChanged", function(self, width, height)
    content:SetWidth(scrollFrame:GetWidth())
end)

local logEntries = {}

local function AddDeathEntry(victim, killer, zone, timeStr)
    local entry = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    entry:SetJustifyH("LEFT")
    entry:SetWidth(content:GetWidth())
    
    -- Format text: [Time] Victim slain by Killer (Zone)
    local formattedLine = string.format("|cff808080[%s]|r |cffFFD700%s|r killed by |cffFF4500%s|r in |cff00FFFF%s|r", 
                                        timeStr, victim, killer, zone)
    entry:SetText(formattedLine)
    
    table.insert(logEntries, entry)
    
    -- Layout entries vertically
    local offsetY = 0
    for i = #logEntries, 1, -1 do
        local item = logEntries[i]
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -offsetY)
        item:SetWidth(content:GetWidth())
        offsetY = offsetY + item:GetStringHeight() + 4
    end
    
    content:SetHeight(math.max(offsetY, scrollFrame:GetHeight()))
    scrollFrame:SetVerticalScroll(0) -- Auto-scroll to latest at the top
end

----------------------------------------------------
-- 5. Event Listener & Sync Processing
----------------------------------------------------
local eventHandler = CreateFrame("Frame")
eventHandler:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventHandler:RegisterEvent("CHAT_MSG_ADDON")

eventHandler:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subEvent, hideCaster, 
              sourceGUID, sourceName, sourceFlags, sourceFlags2, 
              destGUID, destName, destFlags, destFlags2 = CombatLogGetCurrentEventInfo()
              
        if subEvent == "UNIT_DIED" then
            local idType = strsplit("-", destGUID or "")
            if idType == "Player" then
                -- Verify if the deceased player is in your guild
                local isGuildMember = false
                if IsInGuild() then
                    for i = 1, GetNumGuildMembers() do
                        local name = GetGuildRosterInfo(i)
                        if name and strcmputil and strcmputil(name, destName) or (name and name:find(destName)) then
                            isGuildMember = true
                            break
                        end
                    end
                end

                -- If the local player dies or a detected guild member dies locally
                if destName == UnitName("player") or isGuildMember then
                    local zoneText = GetRealZoneText() or "Unknown Zone"
                    local exactTime = date("%H:%M")
                    local killerName = sourceName or "Environment/NPC"

                    local payload = string.format("%s|%s|%s|%s", destName, killerName, zoneText, exactTime)
                    
                    -- Quietly broadcast to all online guild members with the addon
                    if IsInGuild() then
                        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, payload, "GUILD")
                    end
                end
            end
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = ...
        if prefix == ADDON_PREFIX and channel == "GUILD" then
            local victim, killer, zone, tTime = strsplit("|", text)
            if victim and killer and zone and tTime then
                AddDeathEntry(victim, killer, zone, tTime)
            end
        end
    end
end)

----------------------------------------------------
-- 6. Slash Command to Toggle Window
----------------------------------------------------
SLASH_GUILDDEATHS1 = "/gdb"
SLASH_GUILDDEATHS2 = "/guilddeaths"
SlashCmdList["GUILDDEATHS"] = function()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end