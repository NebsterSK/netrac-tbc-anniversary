-- Netrac quest planner: your XP bar and the quests in your log, with a tick box per quest.
-- Finished quests are ticked when you open it; tick the others you plan to turn in; the bar shows how far they take you and whether you ding.
-- Read-only: it only reads your quest log and XP, nothing is sent anywhere. /nqxp toggles the window.

local ROW_H, WIDTH, MAX_ROWS = 18, 340, 25
local frame, bar, planTex, overTex, barText, infoText, emptyText
local rows = {}
local list = {}

-- Quest XP at your level: Questie's QuestXP module (same as the quest log line), else the game's value.
local QXP
local function questXP(questID)
  if not questID or questID == 0 then return nil end
  if QXP == nil then
    QXP = false
    local loader = rawget(_G, "QuestieLoader")
    if type(loader) == "table" and loader.ImportModule then
      local ok, m = pcall(loader.ImportModule, loader, "QuestXP")
      if ok and type(m) == "table" and type(m.GetQuestLogRewardXP) == "function" and type(m.db) == "table" then QXP = m end
    end
  end
  if QXP then
    local ok, xp = pcall(QXP.GetQuestLogRewardXP, QXP, questID, false)
    if ok and type(xp) == "number" and xp > 0 then return xp end
  end
end

local function plan()
  NEB_CharLogDB = NEB_CharLogDB or {}
  NEB_CharLogDB.questPlan = NEB_CharLogDB.questPlan or {}
  return NEB_CharLogDB.questPlan
end

local function fmt(n)
  local s = tostring(math.floor(n + 0.5))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

local function readLog()
  wipe(list)
  local n = GetNumQuestLogEntries() or 0
  for i = 1, n do
    local title, level, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
    if title and not isHeader and questID and questID > 0 then
      list[#list + 1] = { id = questID, title = title, level = level or 0,
        complete = (isComplete == 1 or isComplete == true), xp = questXP(questID) }
    end
  end
  table.sort(list, function(a, b)
    if a.complete ~= b.complete then return a.complete end
    local ax, bx = a.xp or 0, b.xp or 0
    if ax ~= bx then return ax > bx end
    return a.title < b.title
  end)
  -- forget ticks for quests that left the log
  local p, inLog = plan(), {}
  for _, q in ipairs(list) do inLog[q.id] = true end
  for id in pairs(p) do if not inLog[id] then p[id] = nil end end
end

local function refresh()
  if not frame or not frame:IsShown() then return end
  readLog()
  local p = plan()
  local cur, max, level = UnitXP("player") or 0, UnitXPMax("player") or 1, UnitLevel("player") or 1
  if max <= 0 then max = 1 end
  local sum, count = 0, 0
  for i, q in ipairs(list) do
    local r = rows[i]
    if r then
      r.questID = q.id
      r.check:SetChecked(p[q.id] and true or false)
      local c = GetQuestDifficultyColor and GetQuestDifficultyColor(q.level) or { r = 1, g = 1, b = 1 }
      local mark = q.complete and " |cff20ff20(done)|r" or ""
      r.name:SetText(("[%d] %s%s"):format(q.level, q.title, mark))
      r.name:SetTextColor(c.r, c.g, c.b)
      r.xp:SetText(q.xp and fmt(q.xp) or "?")
      r:Show()
      if p[q.id] then sum = sum + (q.xp or 0); count = count + 1 end
    end
  end
  for i = #list + 1, MAX_ROWS do if rows[i] then rows[i]:Hide() end end
  emptyText:SetShown(#list == 0)

  local barW = bar:GetWidth()
  bar:SetMinMaxValues(0, max)
  bar:SetValue(cur)
  local startX = barW * cur / max
  local endXP = math.min(cur + sum, max)
  local w = barW * (endXP - cur) / max
  if w > 0.5 then
    planTex:ClearAllPoints()
    planTex:SetPoint("TOPLEFT", bar, "TOPLEFT", startX, 0)
    planTex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", startX, 0)
    planTex:SetWidth(w)
    planTex:Show()
  else
    planTex:Hide()
  end
  overTex:SetShown(cur + sum >= max)
  barText:SetText(("%s / %s  (%.0f%%)"):format(fmt(cur), fmt(max), cur / max * 100))

  local need = max - cur
  local info
  if count == 0 then
    info = ("Level %d: %s XP to %d. Tick the quests you plan to turn in."):format(level, fmt(need), level + 1)
  elseif cur + sum >= max then
    info = ("%d ticked: +%s XP. |cff20ff20Ding %d|r with %s XP to spare (%.2f)."):format(count, fmt(sum), level + 1,
      fmt(cur + sum - max), level + 1 + (cur + sum - max) / max)
  else
    info = ("%d ticked: +%s XP, to %.2f. Still %s XP short of %d."):format(count, fmt(sum), level + math.floor((cur + sum) / max * 100) / 100,
      fmt(max - cur - sum), level + 1)
  end
  infoText:SetText(info)
  frame:SetHeight(108 + math.max(1, math.min(#list, MAX_ROWS)) * ROW_H)
end

local pending = false
local function queueRefresh()
  if pending or not frame or not frame:IsShown() then return end
  pending = true
  C_Timer.After(0.2, function() pending = false; refresh() end)
end

local function build()
  frame = CreateFrame("Frame", "NetracQuestPlanFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(WIDTH, 200)
  local pos = NEB_CharLogDB and NEB_CharLogDB.questPlanPos
  if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80) end
  frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0, 0, 0, 0.8)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    NEB_CharLogDB = NEB_CharLogDB or {}
    NEB_CharLogDB.questPlanPos = { p, rp, x, y }
  end)
  frame:SetScript("OnShow", function()   -- finished quests start ticked each time you open the window
    readLog()
    local p = plan()
    for _, q in ipairs(list) do if q.complete then p[q.id] = true end end
    refresh()
  end)
  frame:Hide()
  tinsert(UISpecialFrames, "NetracQuestPlanFrame")   -- Escape closes it

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -9)
  title:SetText("|cff66ccffNetrac|r quest XP planner")
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  bar = CreateFrame("StatusBar", nil, frame)
  bar:SetPoint("TOPLEFT", 10, -30)
  bar:SetSize(WIDTH - 20, 16)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(0.58, 0.0, 0.55)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(bar)
  bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
  planTex = bar:CreateTexture(nil, "ARTWORK")
  planTex:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
  planTex:SetVertexColor(0.1, 0.85, 0.2, 0.9)
  overTex = bar:CreateTexture(nil, "OVERLAY")
  overTex:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
  overTex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  overTex:SetWidth(3)
  overTex:SetColorTexture(1, 0.85, 0.1, 1)
  barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  barText:SetPoint("CENTER")

  infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  infoText:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -5)
  infoText:SetWidth(WIDTH - 20)
  infoText:SetJustifyH("LEFT")

  local function button(text, x, onClick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(96, 18)
    b:SetPoint("BOTTOMLEFT", x, 8)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
  end
  button("Tick done", 10, function()
    local p = plan()
    for _, q in ipairs(list) do if q.complete then p[q.id] = true end end
    refresh()
  end)
  button("Clear", 110, function() wipe(plan()); refresh() end)

  for i = 1, MAX_ROWS do
    local r = CreateFrame("Frame", nil, frame)
    r:SetSize(WIDTH - 20, ROW_H)
    r:SetPoint("TOPLEFT", 10, -80 - (i - 1) * ROW_H)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(20, 20)
    r.check:SetPoint("LEFT", -2, 0)
    r.check:SetScript("OnClick", function(self)
      if r.questID then plan()[r.questID] = self:GetChecked() and true or nil end
      refresh()
    end)
    r.xp = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.xp:SetPoint("RIGHT", 0, 0)
    r.xp:SetJustifyH("RIGHT")
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.check, "RIGHT", 0, 0)
    r.name:SetPoint("RIGHT", r.xp, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r:Hide()
    rows[i] = r
  end
  emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  emptyText:SetPoint("TOPLEFT", 12, -82)
  emptyText:SetText("Your quest log is empty.")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("PLAYER_XP_UPDATE")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then build() return end
  queueRefresh()
end)

SLASH_NETRACQXP1 = "/nqxp"
SLASH_NETRACQXP2 = "/netracxp"
SlashCmdList["NETRACQXP"] = function()
  if not frame then build() end
  if frame:IsShown() then frame:Hide() else frame:Show() end
end
