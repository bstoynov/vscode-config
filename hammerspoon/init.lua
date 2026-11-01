-- Hammerspoon window snapping
-- Rectangle-style shortcuts + fourths + cycling on repeated presses.
-- Windows that refuse the requested size (e.g. the iOS Simulator, which
-- keeps a fixed aspect ratio) are centered inside their slot instead of
-- being pinned to its edge.

hs.window.animationDuration = 0

local TOL = 2 -- px tolerance when comparing frames

local hyper = { "ctrl", "alt" }

---------------------------------------------------------------------------
-- Positions: { x, y, w, h } as fractions of the screen's usable area
-- (menu bar and Dock excluded). Each action is a list of steps; pressing
-- the same shortcut again moves to the next step.
---------------------------------------------------------------------------
local F1 = { 0,   0, 1/4, 1 }
local F2 = { 1/4, 0, 1/4, 1 }
local F3 = { 1/2, 0, 1/4, 1 }
local F4 = { 3/4, 0, 1/4, 1 }

local actions = {
  -- halves (no cycling)
  leftHalf          = { { 0, 0, 1/2, 1 } },
  rightHalf         = { { 1/2, 0, 1/2, 1 } },
  topHalf           = { { 0, 0, 1, 1/2 } },
  bottomHalf        = { { 0, 1/2, 1, 1/2 } },

  -- quarters
  topLeft           = { { 0, 0, 1/2, 1/2 } },
  topRight          = { { 1/2, 0, 1/2, 1/2 } },
  bottomLeft        = { { 0, 1/2, 1/2, 1/2 } },
  bottomRight       = { { 1/2, 1/2, 1/2, 1/2 } },

  -- thirds: first/last cycle across the screen
  firstThird        = { { 0, 0, 1/3, 1 }, { 1/3, 0, 1/3, 1 }, { 2/3, 0, 1/3, 1 } },
  centerThird       = { { 1/3, 0, 1/3, 1 } },
  lastThird         = { { 2/3, 0, 1/3, 1 }, { 1/3, 0, 1/3, 1 }, { 0, 0, 1/3, 1 } },
  firstTwoThirds    = { { 0, 0, 2/3, 1 }, { 1/3, 0, 2/3, 1 } },
  lastTwoThirds     = { { 1/3, 0, 2/3, 1 }, { 0, 0, 2/3, 1 } },

  -- fourths: first/last cycle across the screen
  firstFourth       = { F1, F2, F3, F4 },
  secondFourth      = { F2 },
  thirdFourth       = { F3 },
  lastFourth        = { F4, F3, F2, F1 },
  firstThreeFourths = { { 0, 0, 3/4, 1 }, { 1/4, 0, 3/4, 1 } },
  lastThreeFourths  = { { 1/4, 0, 3/4, 1 }, { 0, 0, 3/4, 1 } },

  maximize          = { { 0, 0, 1, 1 } },
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local cycle = {}         -- [winId] = { action, index, frame }
local restoreFrames = {} -- [winId] = frame right before the last snap

local function same(a, b)
  return a ~= nil and b ~= nil
    and math.abs(a.x - b.x) <= TOL and math.abs(a.y - b.y) <= TOL
    and math.abs(a.w - b.w) <= TOL and math.abs(a.h - b.h) <= TOL
end

local function unitToRect(screen, u)
  local s = screen:frame()
  return hs.geometry.rect(
    math.floor(s.x + u[1] * s.w + 0.5),
    math.floor(s.y + u[2] * s.h + 0.5),
    math.floor(u[3] * s.w + 0.5),
    math.floor(u[4] * s.h + 0.5)
  )
end

local function clampToScreen(f, s)
  f.x = math.max(s.x, math.min(f.x, s.x + s.w - f.w))
  f.y = math.max(s.y, math.min(f.y, s.y + s.h - f.h))
  return f
end

-- Save the frame before every move, so Restore goes back one step:
-- to wherever the window was right before the last snap.
local function remember(win)
  restoreFrames[win:id()] = win:frame()
end

local function finish(win, actionName, index)
  local id = win:id()
  local f = win:frame()
  if actionName then
    cycle[id] = { action = actionName, index = index, frame = f }
  else
    cycle[id] = nil
  end
end

-- Windows that ignored a resize entirely (e.g. the iOS Simulator).
-- Once known, they are only ever moved, never resized, so they don't
-- flash at the slot's top-left corner before being centered.
local fixedSize = {} -- [winId] = true

local function moveCentered(win, slot, screen)
  local f = win:frame()
  f.x = slot.x + (slot.w - f.w) / 2
  f.y = slot.y + (slot.h - f.h) / 2
  f = clampToScreen(f, screen:frame())
  win:setTopLeft(hs.geometry.point(f.x, f.y))
end

-- Put a window into a slot. If it won't take the slot's size,
-- center it inside the slot with equal margins.
local function place(win, slot, screen)
  local id = win:id()
  if fixedSize[id] then
    moveCentered(win, slot, screen)
    return
  end
  local before = win:frame()
  win:setFrame(slot, 0)
  local f = win:frame()
  if math.abs(f.w - slot.w) > TOL or math.abs(f.h - slot.h) > TOL then
    -- Flag it as fixed-size only if it was asked to grow and its size
    -- didn't change at all. A window sitting at its minimum size also
    -- keeps its size when asked to shrink, so that alone isn't enough.
    -- The 50px margin ignores terminals that resize in whole character
    -- cells and end up a few pixels short of the slot.
    local GROW_MARGIN = 50
    local unchanged = math.abs(f.w - before.w) <= TOL and math.abs(f.h - before.h) <= TOL
    local askedToGrow = slot.w > before.w + GROW_MARGIN or slot.h > before.h + GROW_MARGIN
    if unchanged and askedToGrow then
      fixedSize[id] = true
    end
    moveCentered(win, slot, screen)
  end
end

local function focused()
  local win = hs.window.focusedWindow()
  if win and win:isStandard() then return win end
  return nil
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function snap(name)
  return function()
    local win = focused()
    if not win then return end
    local steps = actions[name]
    local c = cycle[win:id()]
    local i = 1
    if c and c.action == name and same(win:frame(), c.frame) then
      i = c.index % #steps + 1
    end
    remember(win)
    local screen = win:screen()
    place(win, unitToRect(screen, steps[i]), screen)
    finish(win, name, i)
  end
end

local function center()
  local win = focused()
  if not win then return end
  remember(win)
  local s = win:screen():frame()
  local f = win:frame()
  f.x = s.x + (s.w - f.w) / 2
  f.y = s.y + (s.h - f.h) / 2
  win:setFrame(clampToScreen(f, s), 0)
  finish(win)
end

local function restore()
  local win = focused()
  if not win then return end
  local id = win:id()
  local f = restoreFrames[id]
  if f then
    win:setFrame(f, 0)
    restoreFrames[id] = nil
    cycle[id] = nil
  end
end

---------------------------------------------------------------------------
-- Shortcuts (Rectangle defaults where Rectangle has one)
---------------------------------------------------------------------------
local bindings = {
  { hyper, "left",   snap("leftHalf") },
  { hyper, "right",  snap("rightHalf") },
  { hyper, "up",     snap("topHalf") },
  { hyper, "down",   snap("bottomHalf") },

  { hyper, "u",      snap("topLeft") },
  { hyper, "i",      snap("topRight") },
  { hyper, "j",      snap("bottomLeft") },
  { hyper, "k",      snap("bottomRight") },

  -- thirds
  { hyper, "d",      snap("firstThird") },       -- first -> center -> last third
  { hyper, "t",      snap("lastTwoThirds") },    -- right 2/3 -> left 2/3

  -- fourths
  { hyper, "f",      snap("firstFourth") },      -- 1st -> 2nd -> 3rd -> 4th fourth
  { hyper, "y",      snap("lastThreeFourths") }, -- right 3/4 -> left 3/4

  -- other
  { hyper, "return", snap("maximize") },
  { hyper, "c",      center },
  { hyper, "delete", restore },
}

for _, b in ipairs(bindings) do
  hs.hotkey.bind(b[1], b[2], b[3])
end

---------------------------------------------------------------------------
-- Reload automatically when this file changes
---------------------------------------------------------------------------
configWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(files)
  for _, file in ipairs(files) do
    if file:sub(-4) == ".lua" then
      hs.reload()
      return
    end
  end
end):start()

hs.alert.show("Window snapping loaded")
