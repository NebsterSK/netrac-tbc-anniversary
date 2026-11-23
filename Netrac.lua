-- Netrac (Nebster Tracking), formerly NEB CharLog: read-only snapshot of the player's own character.
-- Only uses normal game API and SavedVariables. No network, no secure frames; the combat log is only read.
-- One post-hook on the quest log adds the selected quest's XP under its rewards (display only).
-- v0.2 adds tracking: XP by source (zone, RestedXP guide, level), kills, deaths, gold by source, loot, dungeon runs.
local ADDON = "NEB_CharLog"
local f = CreateFrame("Frame")
local db
local playedTotal, playedAt  -- seconds played at the time of the last TIME_PLAYED_MSG, and GetTime() then
local origDisplay, silentPlayed = nil, false

local function safe(fn, ...)
  local ok, a, b, c, d, e, g, h, i, j, k = pcall(fn, ...)
  if ok then return a, b, c, d, e, g, h, i, j, k end
  return nil
end

local function playedNow()
  if playedTotal and playedAt then return math.floor(playedTotal + (GetTime() - playedAt)) end
end

local function requestPlayed()
  -- hide the chat spam while this request is answered
  if ChatFrame_DisplayTimePlayed and not silentPlayed then
    origDisplay = ChatFrame_DisplayTimePlayed
    ChatFrame_DisplayTimePlayed = function() end
    silentPlayed = true
  end
  RequestTimePlayed()
end

local function equipment()
  local t = {}
  for slot = 1, 19 do
    local link = GetInventoryItemLink("player", slot)
    if link then t[slot] = link end
  end
  return t
end

local function stats()
  local s = {}
  local names = { "str", "agi", "sta", "int", "spi" }
  for i = 1, 5 do
    local base, eff = UnitStat("player", i)
    s[names[i]] = eff or base
  end
  s.healthMax = UnitHealthMax("player")
  s.manaMax = UnitPowerMax("player", 0)
  s.armor = safe(function() local _, eff = UnitArmor("player"); return eff end)
  s.spellDmgShadow = safe(GetSpellBonusDamage, 6)
  s.spellDmgFire = safe(GetSpellBonusDamage, 3)
  s.spellCritShadow = safe(GetSpellCritChance, 6)
  s.spellHitBonus = safe(function() return GetCombatRatingBonus(CR_HIT_SPELL) end)
  s.spellHaste = safe(function() return GetCombatRatingBonus(CR_HASTE_SPELL) end)
  s.mp5 = safe(function() return GetManaRegen() * 5 end)
  s.freeBagSlots = safe(function()
    local n = 0
    local f = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    for bag = 0, 4 do n = n + (f and f(bag) or 0) end
    return n
  end)
  return s
end

local function talents()
  local out = {}
  local tabs = safe(GetNumTalentTabs) or 0
  for tab = 1, tabs do
    local a, b, c, d, e = GetTalentTabInfo(tab)
    local name, spent = a, b
    if type(a) == "number" then name, spent = b, e end
    if type(spent) ~= "number" then spent = (type(c) == "number" and c) or (type(d) == "number" and d) or 0 end
    local entry = { name = name, points = spent, ranks = {} }
    for idx = 1, (safe(GetNumTalents, tab) or 0) do
      local tname, _, _, _, rank = GetTalentInfo(tab, idx)
      if tname and rank and rank > 0 then entry.ranks[tname] = rank end
    end
    out[#out + 1] = entry
  end
  return out
end

local function professions()
  local out = {}
  for i = 1, (safe(GetNumSkillLines) or 0) do
    local name, header, _, rank, _, _, maxRank = GetSkillLineInfo(i)
    if name and not header then out[#out + 1] = name .. " " .. tostring(rank) .. "/" .. tostring(maxRank) end
  end
  return out
end

local function quests()
  local out = {}
  local n = safe(GetNumQuestLogEntries) or 0
  for i = 1, n do
    local title, level, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
    if title and not isHeader then
      out[#out + 1] = { title = title, level = level, id = questID, complete = isComplete and true or false }
    end
  end
  return out
end

local function spells()
  local out = {}
  for tab = 1, (safe(GetNumSpellTabs) or 0) do
    local tname, _, offset, num = GetSpellTabInfo(tab)
    if tname and tname ~= "General" then
      for i = offset + 1, offset + num do
        local name, rank = GetSpellBookItemName(i, "spell")
        if name then out[#out + 1] = name .. (rank and rank ~= "" and (" (" .. rank .. ")") or "") end
      end
    end
  end
  return out
end

local function location()
  local x, y
  local map = safe(function() return C_Map.GetBestMapForUnit("player") end)
  if map then
    local pos = safe(function() return C_Map.GetPlayerMapPosition(map, "player") end)
    if pos then x, y = pos.x * 100, pos.y * 100 end
  end
  return { zone = GetZoneText(), subzone = GetSubZoneText(), x = x and math.floor(x * 10) / 10, y = y and math.floor(y * 10) / 10 }
end

local function snapshot(reason)
  if not db then return end
  local class = select(2, UnitClass("player"))
  local snap = {
    reason = reason,
    time = time(),
    date = date("%Y-%m-%d %H:%M:%S"),
    name = UnitName("player"),
    realm = GetRealmName(),
    race = UnitRace("player"),
    class = class,
    level = UnitLevel("player"),
    xp = UnitXP("player"),
    xpMax = UnitXPMax("player"),
    restedXp = GetXPExhaustion(),
    money = GetMoney(),
    playedSeconds = playedNow(),
    location = location(),
    stats = safe(stats),
    equipment = safe(equipment),
    talents = safe(talents),
    professions = safe(professions),
    quests = safe(quests),
    spells = safe(spells),
    pet = UnitExists("pet") and { name = UnitName("pet"), family = UnitCreatureFamily("pet"), level = UnitLevel("pet") } or nil,
    build = select(4, GetBuildInfo()),
  }
  db.snapshot = snap
end

local function logLevel(level)
  db.levels = db.levels or {}
  db.levels[level] = { time = time(), date = date("%Y-%m-%d %H:%M:%S"), zone = GetZoneText(), played = playedNow() }
end

-- ===== Tracking (v0.2): XP by source, kills, deaths, gold by source, loot, dungeon runs =====
-- Everything below only listens to events and reads values the game already shows you.
-- The combat log is read only to remember what last hit you (for the death log).

local playerGUID
local lastLevel, lastXP, lastMax, lastMoney
local lastAttacker, lastAttackerAt
local currentRun
local hasTurnedInEvent = false
local ctx = { merchant = false, trainer = false, taxi = false, mail = false, loot = false, quest = false, questUntil = 0, lootUntil = 0, lootFrom = nil }
local lastOtherIn   -- last unexplained income, in case the "You loot ..." line arrives after the money

local function cap(list, n)
  while #list > n do table.remove(list, 1) end
end

local function guideName()
  local d = rawget(_G, "RXPCData")
  if type(d) == "table" and type(d.currentGuideName) == "string" then return d.currentGuideName end
  return "none"
end

local function levelNow()
  local lvl, xp, mx = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
  if mx and mx > 0 then return math.floor((lvl + xp / mx) * 100) / 100 end
  return lvl
end

local function toPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%s", "(.-)")
  p = p:gsub("%%d", "(%%d+)")
  return "^" .. p .. "$"
end

-- XP buckets: by zone, by RestedXP guide, by character level, and the current dungeon run.
-- Fields: total (all XP), quest, kill, rested (part of kill), explore, quests, kills. Other = total - quest - kill - explore.
local function addXP(fields)
  db.xp = db.xp or {}
  db.xp.byZone = db.xp.byZone or {}
  db.xp.byGuide = db.xp.byGuide or {}
  db.xp.byLevel = db.xp.byLevel or {}
  local keys = { db.xp.byZone, GetZoneText() or "?", db.xp.byGuide, guideName(), db.xp.byLevel, UnitLevel("player") }
  for i = 1, #keys, 2 do
    local t, k = keys[i], keys[i + 1]
    t[k] = t[k] or {}
    for field, v in pairs(fields) do t[k][field] = (t[k][field] or 0) + v end
  end
  if currentRun then
    for field, v in pairs(fields) do currentRun[field] = (currentRun[field] or 0) + v end
  end
end

local function onXPUpdate()
  local lvl, xp, mx = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
  if lastLevel and lastXP and lastMax then
    local d
    if lvl == lastLevel and xp >= lastXP then
      d = xp - lastXP
    elseif lvl > lastLevel or xp < lastXP then
      d = (lastMax - lastXP) + xp
      if lvl == lastLevel then lvl = lvl + 1 end   -- level-up seen before UnitLevel updates
    end
    if d and d > 0 then addXP({ total = d }) end
  end
  lastLevel, lastXP, lastMax = lvl, xp, mx
end

-- kill XP from the "X dies, you gain N experience." messages
local XPPATS
local function buildXPPatterns()
  XPPATS = {}
  local list = {
    { "COMBATLOG_XPGAIN_EXHAUSTION1_GROUP", true }, { "COMBATLOG_XPGAIN_EXHAUSTION1_RAID", true }, { "COMBATLOG_XPGAIN_EXHAUSTION1", true },
    { "COMBATLOG_XPGAIN_EXHAUSTION2_GROUP" }, { "COMBATLOG_XPGAIN_EXHAUSTION2_RAID" }, { "COMBATLOG_XPGAIN_EXHAUSTION2" },
    { "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP" }, { "COMBATLOG_XPGAIN_FIRSTPERSON_RAID" }, { "COMBATLOG_XPGAIN_FIRSTPERSON" },
  }
  for _, e in ipairs(list) do
    local p = toPattern(rawget(_G, e[1]))
    if p then XPPATS[#XPPATS + 1] = { p, e[2] } end
  end
end

local function onKillXP(msg)
  if type(msg) ~= "string" then return end
  if not XPPATS then buildXPPatterns() end
  for _, e in ipairs(XPPATS) do
    local name, xp, rest = msg:match(e[1])
    xp = tonumber(xp)
    if name and xp then
      local rested = e[2] and tonumber((rest or ""):match("%d+")) or 0
      addXP({ kill = xp, rested = rested, kills = 1 })
      local zone = GetZoneText() or "?"
      db.kills = db.kills or {}
      db.kills[zone] = db.kills[zone] or {}
      local k = db.kills[zone][name] or { n = 0, xp = 0 }
      k.n = k.n + 1
      k.xp = k.xp + xp
      k.lastLevel = UnitLevel("player")
      db.kills[zone][name] = k
      return
    end
  end
end

local function logTurnIn(questID, xp, money)
  db.turnins = db.turnins or {}
  local title
  local ok, t = pcall(function() return C_QuestLog and C_QuestLog.GetQuestInfo and C_QuestLog.GetQuestInfo(questID) end)
  if ok and type(t) == "string" then title = t end
  db.turnins[#db.turnins + 1] = { id = questID, title = title, xp = xp, money = money, level = levelNow(), zone = GetZoneText(), guide = guideName(), date = date("%Y-%m-%d %H:%M:%S") }
  cap(db.turnins, 3000)
end

local function onQuestTurnedIn(questID, xpReward, moneyReward)
  hasTurnedInEvent = true
  ctx.questUntil = GetTime() + 2
  addXP({ quest = xpReward or 0, quests = 1 })
  logTurnIn(questID, xpReward or 0, moneyReward or 0)
end

-- system messages: exploration XP, and quest XP as a fallback when QUEST_TURNED_IN is not available
local SYS
local function onSystem(msg)
  if type(msg) ~= "string" then return end
  if not SYS then SYS = { explore = toPattern(rawget(_G, "ERR_ZONE_EXPLORED_XP")), quest = toPattern(rawget(_G, "ERR_QUEST_REWARD_EXP_I")) } end
  if SYS.explore then
    local _, xp = msg:match(SYS.explore)
    if tonumber(xp) then addXP({ explore = tonumber(xp) }); return end
  end
  if SYS.quest and not hasTurnedInEvent then
    local xp = msg:match(SYS.quest)
    if tonumber(xp) then addXP({ quest = tonumber(xp), quests = 1 }); ctx.questUntil = GetTime() + 2 end
  end
end

-- gold by source, per character level
local function onMoney()
  local m = GetMoney()
  if lastMoney then
    local d = m - lastMoney
    if d ~= 0 then
      local src
      if ctx.quest or GetTime() < ctx.questUntil then src = "quest"
      elseif ctx.loot or GetTime() < ctx.lootUntil then src = "loot"
      elseif ctx.merchant then src = (d > 0) and "vendorSold" or "merchantSpent"
      elseif ctx.trainer then src = "trainer"
      elseif ctx.taxi then src = "flights"
      elseif ctx.mail then src = "mail"
      else src = (d > 0) and "otherIn" or "otherOut" end
      db.gold = db.gold or {}
      local lv = UnitLevel("player")
      db.gold[lv] = db.gold[lv] or {}
      db.gold[lv][src] = (db.gold[lv][src] or 0) + d
      if src == "otherIn" then lastOtherIn = { amount = d, at = GetTime(), lv = lv } end
      if currentRun then currentRun.gold = (currentRun.gold or 0) + d end
    end
  end
  lastMoney = m
end

-- coins you loot ("You loot 1 Silver 20 Copper", "Your share of the loot is ..."): with auto-loot the money can land
-- before the loot window event, so the chat line marks it as loot too
local function onLootMoney(msg)
  if type(msg) ~= "string" then return end
  local amount = 0
  local function add(n, unit)
    unit = unit:lower()
    if unit:find("^gold") then amount = amount + tonumber(n) * 10000
    elseif unit:find("^silver") then amount = amount + tonumber(n) * 100
    elseif unit:find("^copper") then amount = amount + tonumber(n) end
  end
  -- coin icons ("52|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t") or words ("52 Copper")
  for n, unit in msg:gmatch("(%d+)%s*|T[^|]-UI%-(%a+)Icon") do add(n, unit) end
  if amount == 0 then
    for n, unit in msg:gmatch("(%d+)%s*(%a+)") do add(n, unit) end
  end
  if amount <= 0 then return end
  if lastOtherIn and GetTime() - lastOtherIn.at < 3 and lastOtherIn.amount >= amount then
    local g = db.gold and db.gold[lastOtherIn.lv]
    if g then
      g.otherIn = (g.otherIn or 0) - amount
      if g.otherIn == 0 then g.otherIn = nil end
      g.loot = (g.loot or 0) + amount
    end
    lastOtherIn.amount = lastOtherIn.amount - amount
    if lastOtherIn.amount <= 0 then lastOtherIn = nil end
  else
    ctx.lootUntil = GetTime() + 2
  end
end

-- loot log: green or better items you receive
local QCOLOR = { ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5 }
local LOOTPATS
local function onLoot(msg)
  if type(msg) ~= "string" then return end
  if not LOOTPATS then
    LOOTPATS = {}
    for _, e in ipairs({ { "LOOT_ITEM_SELF_MULTIPLE", "loot" }, { "LOOT_ITEM_SELF", "loot" }, { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "received" },
                         { "LOOT_ITEM_PUSHED_SELF", "received" }, { "LOOT_ITEM_CREATED_SELF_MULTIPLE", "created" }, { "LOOT_ITEM_CREATED_SELF", "created" } }) do
      local p = toPattern(rawget(_G, e[1]))
      if p then LOOTPATS[#LOOTPATS + 1] = { p, e[2] } end
    end
  end
  for _, e in ipairs(LOOTPATS) do
    local link = msg:match(e[1])
    if link then
      local _, _, quality = GetItemInfo(link)
      if not quality then
        local col = link:match("|cff(%x%x%x%x%x%x)")
        quality = col and QCOLOR[col:lower()] or 1
      end
      if quality >= 2 then
        local loc = location()
        db.loot = db.loot or {}
        db.loot[#db.loot + 1] = { item = link, quality = quality, how = e[2], from = (e[2] == "loot") and ctx.lootFrom or nil,
                                  level = levelNow(), zone = loc.zone, subzone = loc.subzone, guide = guideName(), date = date("%Y-%m-%d %H:%M:%S") }
        cap(db.loot, 1000)
        if currentRun then currentRun.loot = currentRun.loot or {}; table.insert(currentRun.loot, link) end
      end
      return
    end
  end
end

-- deaths: where, when, level and what hit you last
local function onCombatLog()
  local _, sub, _, srcGUID, srcName, _, _, dstGUID = CombatLogGetCurrentEventInfo()
  if dstGUID == playerGUID and srcName and srcGUID ~= playerGUID and sub and sub:find("_DAMAGE$") then
    lastAttacker, lastAttackerAt = srcName, GetTime()
  end
end

local lastDeathAt = 0
local function onDeath()
  if GetTime() - lastDeathAt < 10 then return end   -- the game can fire the death event twice
  lastDeathAt = GetTime()
  local loc = location()
  db.deaths = db.deaths or {}
  db.deaths[#db.deaths + 1] = { date = date("%Y-%m-%d %H:%M:%S"), time = time(), level = levelNow(), zone = loc.zone, subzone = loc.subzone, x = loc.x, y = loc.y,
                                killer = (lastAttackerAt and GetTime() - lastAttackerAt < 15) and lastAttacker or nil, guide = guideName() }
  cap(db.deaths, 200)
  if currentRun then currentRun.deaths = (currentRun.deaths or 0) + 1 end
end

-- dungeon runs: time inside, XP by source, kills, gold, deaths and drops
local function checkInstance()
  if not db then return end
  local inInst, kind = IsInInstance()
  if inInst and (kind == "party" or kind == "raid") then
    if not currentRun then
      local name = GetInstanceInfo()
      db.runs = db.runs or {}
      local last = db.runs[#db.runs]
      if last and not last.stop and last.name == name and time() - (last.start or 0) < 3 * 3600 then
        currentRun = last   -- same run continued after a /reload
      else
        currentRun = { name = name, kind = kind, start = time(), date = date("%Y-%m-%d %H:%M:%S"), levelStart = levelNow(), guide = guideName() }
        db.runs[#db.runs + 1] = currentRun
        cap(db.runs, 100)
      end
    end
  elseif currentRun then
    currentRun.stop = time()
    currentRun.minutes = math.floor((currentRun.stop - currentRun.start) / 60 + 0.5)
    currentRun.levelEnd = levelNow()
    currentRun = nil
  end
end

local function setCtx(key, on)
  if on then ctx[key] = true else C_Timer.After(1, function() ctx[key] = false end) end
end

-- Quest log: XP of the selected quest, from Questie's TBC values, scaled to your level the way the server does it
-- (full XP until the quest is 6+ levels below you, then 80/60/40/20/10%).
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
  if GetQuestLogRewardXP then
    local ok, xp = pcall(GetQuestLogRewardXP)
    if ok and type(xp) == "number" and xp > 0 then return xp end
  end
end

local xpLine
local REWARD_PARTS = { "QuestLogMoneyFrame", "QuestLogItemReceiveText", "QuestLogItemChooseText", "QuestLogRewardTitleText",
  "QuestLogSpellLearnText", "QuestLogHonorFrame", "QuestLogQuestDescription", "QuestLogObjectivesText" }
local function showQuestXP()
  local title = rawget(_G, "QuestLogQuestTitle")
  if not title or not GetQuestLogSelection then return end
  local parent = title:GetParent()
  if not xpLine then
    xpLine = parent:CreateFontString("NEB_QuestLogXPText", "ARTWORK", "QuestFont")
    xpLine:SetJustifyH("LEFT")
  end
  xpLine:Hide()
  local idx = GetQuestLogSelection()
  if not idx or idx == 0 then return end
  local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(idx)
  if isHeader then return end
  local xp = questXP(questID)
  if not xp then return end
  -- under the lowest visible part of the rewards (money, items, reward header), else under the description
  local anchor, low
  for _, name in ipairs(REWARD_PARTS) do
    local f = rawget(_G, name)
    if f and f.IsShown and f:IsShown() then
      local ok, b = pcall(f.GetBottom, f)
      if ok and b then
        if not low or b < low then anchor, low = f, b end
      elseif not anchor then
        anchor = f
      end
    end
  end
  anchor = anchor or title
  for i = 1, 10 do   -- reward item buttons can sit lower than the texts
    local f = rawget(_G, "QuestLogItem" .. i)
    if f and f:IsShown() then
      local ok, b = pcall(f.GetBottom, f)
      if ok and b and (not low or b < low) then anchor, low = f, b end
    end
  end
  local mx = UnitXPMax("player")
  local pct = (mx and mx > 0) and string.format(" (%d%% of level)", math.floor(xp / mx * 100 + 0.5)) or ""
  local num = BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or tostring(xp)
  xpLine:ClearAllPoints()
  xpLine:SetPoint("LEFT", title, "LEFT", 0, 0)
  xpLine:SetPoint("TOP", anchor, "BOTTOM", 0, -8)
  xpLine:SetText("Experience: " .. num .. pct)
  xpLine:SetTextColor(1, 1, 1)
  xpLine:Show()
end

local function trackingInit()
  if type(QuestLog_UpdateQuestDetails) == "function" and hooksecurefunc then
    hooksecurefunc("QuestLog_UpdateQuestDetails", function() pcall(showQuestXP) end)
  end
  playerGUID = UnitGUID("player")
  lastLevel, lastXP, lastMax = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
  lastMoney = GetMoney()
  db.trackingSince = db.trackingSince or date("%Y-%m-%d %H:%M:%S")
  C_Timer.After(2, checkInstance)
end

local function xpSummary()
  local g = guideName()
  local b = db.xp and db.xp.byGuide and db.xp.byGuide[g]
  if not b then print("|cff66ccffNetrac:|r no XP tracked yet for " .. g .. ".") return end
  local other = (b.total or 0) - (b.quest or 0) - (b.kill or 0) - (b.explore or 0)
  print(string.format("|cff66ccffNetrac:|r %s: quests %d XP (%d turn-ins), kills %d XP (%d kills, %d of it rested), explore %d, other %d. Level now %.2f.",
    g, b.quest or 0, b.quests or 0, b.kill or 0, b.kills or 0, b.rested or 0, b.explore or 0, other, levelNow()))
end

local TRACK = {
  PLAYER_XP_UPDATE = function() onXPUpdate() end,
  CHAT_MSG_COMBAT_XP_GAIN = function(msg) onKillXP(msg) end,
  QUEST_TURNED_IN = function(...) onQuestTurnedIn(...) end,
  CHAT_MSG_SYSTEM = function(msg) onSystem(msg) end,
  PLAYER_MONEY = function() onMoney() end,
  CHAT_MSG_LOOT = function(msg) onLoot(msg) end,
  COMBAT_LOG_EVENT_UNFILTERED = function() onCombatLog() end,
  PLAYER_DEAD = function() onDeath() end,
  PLAYER_ENTERING_WORLD = function() checkInstance() end,
  ZONE_CHANGED_NEW_AREA = function() checkInstance() end,
  MERCHANT_SHOW = function() setCtx("merchant", true) end, MERCHANT_CLOSED = function() setCtx("merchant", false) end,
  TRAINER_SHOW = function() setCtx("trainer", true) end, TRAINER_CLOSED = function() setCtx("trainer", false) end,
  TAXIMAP_OPENED = function() setCtx("taxi", true) end, TAXIMAP_CLOSED = function() setCtx("taxi", false) end,
  MAIL_SHOW = function() setCtx("mail", true) end, MAIL_CLOSED = function() setCtx("mail", false) end,
  QUEST_COMPLETE = function() setCtx("quest", true) end, QUEST_FINISHED = function() setCtx("quest", false) end,
  LOOT_OPENED = function()
    ctx.lootFrom = (UnitExists("target") and UnitIsDead("target")) and UnitName("target") or nil
    setCtx("loot", true)
  end,
  LOOT_CLOSED = function() setCtx("loot", false) end,
  LOOT_READY = function() setCtx("loot", true) end,
  CHAT_MSG_MONEY = function(msg) onLootMoney(msg) end,
}

f:SetScript("OnEvent", function(self, event, ...)
  local h = TRACK[event]
  if h then
    if db then h(...) end
    return
  end
  if event == "PLAYER_LOGIN" then
    NEB_CharLogDB = NEB_CharLogDB or {}
    db = NEB_CharLogDB
    db.sessions = db.sessions or {}
    db.sessions[#db.sessions + 1] = { login = time(), loginDate = date("%Y-%m-%d %H:%M:%S"), level = UnitLevel("player") }
    while #db.sessions > 200 do table.remove(db.sessions, 1) end
    trackingInit()
    if not (db.levels and db.levels[UnitLevel("player")]) then
      db.levels = db.levels or {}
      db.levels[UnitLevel("player")] = { firstSeen = true, time = time(), date = date("%Y-%m-%d %H:%M:%S"), zone = GetZoneText() }
    end
    C_Timer.After(3, function()
      if LoggingCombat and not LoggingCombat() then
        LoggingCombat(true)
        print("|cff66ccffNetrac:|r combat log turned on.")
      end
    end)
    C_Timer.After(5, requestPlayed)
    C_Timer.After(8, function() snapshot("login") end)
    C_Timer.NewTicker(60, function() snapshot("tick") end)
  elseif event == "TIME_PLAYED_MSG" then
    local total, atLevel = ...
    playedTotal, playedAt = total, GetTime()
    if db then db.playedTotal = total; db.playedThisLevel = atLevel; db.playedStamp = time() end
    if silentPlayed then
      C_Timer.After(0.2, function()
        if origDisplay then ChatFrame_DisplayTimePlayed = origDisplay end
        silentPlayed = false
      end)
    end
  elseif event == "PLAYER_LEVEL_UP" then
    local level = ...
    if db then logLevel(level or UnitLevel("player")); snapshot("levelup") end
  elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
    if db then C_Timer.After(1, function() snapshot("change") end) end
  elseif event == "PLAYER_LOGOUT" then
    if db then
      local s = db.sessions[#db.sessions]
      if s then s.logout = time(); s.logoutDate = date("%Y-%m-%d %H:%M:%S"); s.seconds = s.logout - s.login end
    end
  end
end)

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("TIME_PLAYED_MSG")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("CHARACTER_POINTS_CHANGED")
f:RegisterEvent("PLAYER_LOGOUT")
for event in pairs(TRACK) do
  local ok = pcall(f.RegisterEvent, f, event)
  if ok and event == "QUEST_TURNED_IN" then hasTurnedInEvent = true end   -- quest XP from the event, not from the chat line
end

SLASH_NEBCHARLOG1 = "/neblog"
SLASH_NEBCHARLOG2 = "/netrac"
SlashCmdList["NEBCHARLOG"] = function()
  snapshot("manual")
  print("|cff66ccffNetrac:|r snapshot taken. It is written to disk on /reload or logout.")
  if db then xpSummary() end
end
