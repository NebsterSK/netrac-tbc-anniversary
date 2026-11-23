-- NEB_Trainer: small on-screen note with the plan's warlock spells you can learn now,
-- plus the demon abilities (grimoires from the demon trainer) worth buying while you are in town.
-- Reads your own spellbook and your pet's spellbook only. No network, no secure frames, no combat hooks.
-- Part of Netrac (Nebster Tracking). Shown on every load and /reload with the next 3 trainer trips;
-- the close button hides it until the next /reload (or a level-up with a trip due). /nebtrain toggles it.
-- Drag it to move it; the position is saved per character.

-- { learnable at level, spellbook name, rank, trainer trip it belongs to, needs base spell (talent) }
-- Top priority, learned at their own level: Life Tap, Corruption, Immolate, Curse of Agony.
-- The rest waits for the next trip. Trip levels are worked out from this list.
local PLAN = {
  { 4,  "Corruption", 1, 4 },
  { 6,  "Life Tap", 1, 6 },
  { 8,  "Curse of Agony", 1, 8 },
  { 8,  "Fear", 1, 8 },
  { 10, "Drain Soul", 1, 10 },
  { 10, "Immolate", 2, 10 },
  { 14, "Corruption", 2, 14 },
  { 14, "Drain Life", 1, 14 },
  { 16, "Life Tap", 2, 16 },
  { 18, "Curse of Agony", 2, 18 },
  { 20, "Immolate", 3, 20 },
  { 20, "Demon Armor", 1, 20 },
  { 22, "Drain Life", 2, 24 },
  { 24, "Corruption", 3, 24 },
  { 26, "Life Tap", 3, 26 },
  { 28, "Curse of Agony", 3, 28 },
  { 30, "Immolate", 4, 30 },
  { 30, "Drain Life", 3, 30 },
  { 30, "Demon Armor", 2, 30 },
  { 30, "Summon Felsteed", 1, 30 },
  { 34, "Corruption", 4, 34 },
  { 36, "Life Tap", 4, 36 },
  { 38, "Curse of Agony", 4, 38 },
  { 38, "Drain Life", 4, 38 },
  { 38, "Siphon Life", 2, 38, true },
  { 40, "Immolate", 5, 40 },
  { 40, "Demon Armor", 3, 40 },
  { 42, "Death Coil", 1, 44 },
  { 44, "Corruption", 5, 44 },
  { 46, "Life Tap", 5, 46 },
  { 46, "Drain Life", 5, 46 },
  { 48, "Curse of Agony", 5, 48 },
  { 48, "Siphon Life", 3, 48, true },
  { 50, "Immolate", 6, 50 },
  { 50, "Demon Armor", 4, 50 },
  { 50, "Dark Pact", 2, 50, true },
  { 54, "Corruption", 6, 54 },
  { 54, "Drain Life", 6, 54 },
  { 56, "Life Tap", 6, 56 },
  { 58, "Curse of Agony", 6, 58 },
  { 58, "Siphon Life", 4, 58, true },
}
local TRIPS = {}
do
  local seen = {}
  for _, e in ipairs(PLAN) do
    if not seen[e[4]] then seen[e[4]] = true; TRIPS[#TRIPS + 1] = e[4] end
  end
  table.sort(TRIPS)
end

-- Demon abilities (Grimoires, demon trainer). Never a reason for a trip on their own.
-- { level, pet family, ability name, rank, summon spell that unlocks the pet }
local PET = {
  { 14, "Imp", "Blood Pact", 2, "Summon Imp" },
  { 14, "Imp", "Fire Shield", 1, "Summon Imp" },
  { 18, "Imp", "Firebolt", 3, "Summon Imp" },
  { 28, "Succubus", "Lash of Pain", 2, "Summon Succubus" },
  { 36, "Succubus", "Lash of Pain", 3, "Summon Succubus" },
  { 44, "Succubus", "Lash of Pain", 4, "Summon Succubus" },
  { 52, "Succubus", "Lash of Pain", 5, "Summon Succubus" },
  { 28, "Incubus", "Lash of Pain", 2, "Summon Incubus" },
  { 36, "Incubus", "Lash of Pain", 3, "Summon Incubus" },
  { 44, "Incubus", "Lash of Pain", 4, "Summon Incubus" },
  { 52, "Incubus", "Lash of Pain", 5, "Summon Incubus" },
  { 36, "Felhunter", "Spell Lock", 1, "Summon Felhunter" },
  { 38, "Felhunter", "Devour Magic", 2, "Summon Felhunter" },
  { 46, "Felhunter", "Devour Magic", 3, "Summon Felhunter" },
  { 52, "Felhunter", "Spell Lock", 2, "Summon Felhunter" },
  { 54, "Felhunter", "Devour Magic", 4, "Summon Felhunter" },
}

local frame, text

local function knownRanks()
  local k = {}
  for tab = 1, (GetNumSpellTabs() or 0) do
    local _, _, offset, num = GetSpellTabInfo(tab)
    for i = offset + 1, offset + num do
      local name, sub = GetSpellBookItemName(i, "spell")
      if name then
        local r = tonumber((sub or ""):match("(%d+)")) or 1
        if not k[name] or r > k[name] then k[name] = r end
      end
    end
  end
  return k
end

-- Remember the current pet's ability ranks per family (a pet's spellbook is only readable while it is out).
local function scanPet()
  if not NEB_TrainerDB or not UnitExists("pet") then return end
  local family = UnitCreatureFamily("pet")
  local n = HasPetSpells and HasPetSpells()
  if not family or not n or n == 0 then return end
  local k = {}
  for i = 1, n do
    local name, sub = GetSpellBookItemName(i, "pet")
    if name then
      local r = tonumber((sub or ""):match("(%d+)")) or 1
      if not k[name] or r > k[name] then k[name] = r end
    end
  end
  NEB_TrainerDB.pet = NEB_TrainerDB.pet or {}
  NEB_TrainerDB.pet[family] = k
end

local function nextTrips(level, n)
  local out = {}
  for _, t in ipairs(TRIPS) do
    if t > level then out[#out + 1] = t; if #out >= n then break end end
  end
  return out
end

local function nextTrip(level)
  for _, t in ipairs(TRIPS) do
    if t > level then return t end
  end
end

local function compute(level)
  local k = knownRanks()
  local due, later, pets = {}, {}, {}
  for _, e in ipairs(PLAN) do
    local lv, name, rank, trip, needsBase = e[1], e[2], e[3], e[4], e[5]
    local have = k[name] or 0
    if lv <= level and have < rank and (not needsBase or have >= 1) then
      if trip <= level then due[#due + 1] = e else later[#later + 1] = e end
    end
  end
  local petdb = NEB_TrainerDB and NEB_TrainerDB.pet or {}
  for _, e in ipairs(PET) do
    local lv, family, name, rank, summon = e[1], e[2], e[3], e[4], e[5]
    if lv <= level and k[summon] then
      local seen = petdb[family]
      local have = seen and seen[name] or 0
      if have < rank then pets[#pets + 1] = { e, seen == nil } end
    end
  end
  return due, later, pets
end

local function line(e)
  return "  " .. e[2] .. " R" .. e[3] .. " |cff999999(" .. e[1] .. ")|r"
end

local function petLine(p)
  local e, unknown = p[1], p[2]
  return "  " .. e[2] .. ": " .. e[3] .. " R" .. e[4] .. " |cff999999(" .. e[1] .. ")|r"
    .. (unknown and " |cff999999- summon it once to check|r" or "")
end

local function tripLines(level, known)
  local out = {}
  for _, t in ipairs(nextTrips(level, 3)) do
    local items = {}
    for _, e in ipairs(PLAN) do
      if e[4] == t and (not e[5] or (known[e[2]] or 0) >= 1) then items[#items + 1] = e[2] .. " R" .. e[3] end
    end
    if #items > 0 then out[#out + 1] = "  |cffffd100" .. t .. ":|r " .. table.concat(items, ", ") end
  end
  return out
end

local function build()
  frame = CreateFrame("Frame", "NEBTrainerFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(270, 60)
  local pos = NEB_TrainerDB and NEB_TrainerDB.pos
  if pos then
    frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
  end
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  frame:SetBackdropColor(0, 0, 0, 0.75)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(s)
    s:StopMovingOrSizing()
    local p, _, rp, x, y = s:GetPoint()
    NEB_TrainerDB = NEB_TrainerDB or {}
    NEB_TrainerDB.pos = { p, rp, x, y }
  end)
  text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", 8, -8)
  text:SetWidth(242)
  text:SetJustifyH("LEFT")
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetSize(22, 22)
  close:SetPoint("TOPRIGHT", 1, 1)
  close:SetScript("OnClick", function() frame:Hide() end)
  frame:Hide()
end

-- show = true opens the note; false only refreshes it if it is already open
local function refresh(show, level, manual)
  if not frame then build() end
  if not show and not frame:IsShown() then return end
  level = level or UnitLevel("player")
  local due, later, pets = compute(level)
  local nt = nextTrip(level)
  local out = {}
  if #due > 0 then
    out[#out + 1] = "|cff33ff33Trainer: worth a trip now|r"
    for _, e in ipairs(due) do out[#out + 1] = line(e) end
    if #later > 0 then
      out[#out + 1] = "|cffaaaaaaAlso available (buy if you are there):|r"
      for _, e in ipairs(later) do out[#out + 1] = line(e) end
    end
  elseif #later > 0 or #pets > 0 then
    out[#out + 1] = "|cffffcc00Trainer: no trip needed|r" .. (nt and (" (next trip at " .. nt .. ")") or "")
    if #later > 0 then
      out[#out + 1] = "|cffaaaaaaAvailable, can wait:|r"
      for _, e in ipairs(later) do out[#out + 1] = line(e) end
    end
  else
    out[#out + 1] = "|cffaaaaaaTrainer: nothing to learn now.|r"
  end
  if #pets > 0 then
    out[#out + 1] = "|cffcc99ffDemon trainer, buy while in town:|r"
    for _, p in ipairs(pets) do out[#out + 1] = petLine(p) end
  end
  local trips = tripLines(level, knownRanks())
  if #trips > 0 then
    out[#out + 1] = "|cff66ccffNext trainer trips:|r"
    for _, l in ipairs(trips) do out[#out + 1] = l end
  end
  table.insert(out, 1, "|cff66ccffNetrac|r")
  text:SetText(table.concat(out, "\n"))
  frame:SetHeight(text:GetStringHeight() + 16)
  frame:Show()
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(self, event, arg1)
  if event == "PLAYER_LOGIN" then
    NEB_TrainerDB = NEB_TrainerDB or {}
    C_Timer.After(5, scanPet)
    C_Timer.After(6, function() refresh(true) end)
  elseif event == "PLAYER_LEVEL_UP" then
    C_Timer.After(1, function() refresh(true, arg1) end)
  elseif event == "UNIT_PET" or event == "PET_BAR_UPDATE" then
    if event == "UNIT_PET" and arg1 ~= "player" then return end
    C_Timer.After(1, function() scanPet(); refresh(false) end)
  else -- spells learned or changed: update the open note, close it when nothing is left
    C_Timer.After(0.5, function() refresh(false) end)
  end
end)
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("LEARNED_SPELL_IN_TAB")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("UNIT_PET")
ev:RegisterEvent("PET_BAR_UPDATE")

SLASH_NEBTRAIN1 = "/nebtrain"
SlashCmdList["NEBTRAIN"] = function()
  scanPet()
  if frame and frame:IsShown() then frame:Hide() else refresh(true, nil, true) end
end
