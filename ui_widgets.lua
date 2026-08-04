-- ui_widgets.lua
-- Small reusable components built on top of clay.lua (layout) and foley.lua
-- (sound), shared by every demo_*.lua section. Doubles as an example of how
-- to compose Clay elements into stateful-feeling widgets in an immediate-mode
-- UI: callers own the value (pass it in via `value`/`active`), the widget
-- returns the possibly-updated value, and the caller stores it back.

local Clay = require("clay")
local Foley = require("foley")

local Widgets = {}

Widgets.palette = {
  bg      = { 0.078, 0.075, 0.098 },
  panel   = { 0.110, 0.102, 0.141 },
  panel2  = { 0.169, 0.157, 0.212 },
  border  = { 0.22,  0.20,  0.27, 1 },
  text    = { 0.847, 0.831, 0.886 },
  textDim = { 0.498, 0.475, 0.580 },
  pink    = { 0.910, 0.282, 0.608 },
  amber   = { 0.851, 0.604, 0.247 },
  mint    = { 0.388, 0.780, 0.651 },
}

-- id -> was-hovered-last-frame, used to fire a sound once on hover *entry*
-- rather than every frame the pointer sits still over an element.
local hoverWas = {}

local function fireOnEnter(id, hovered, sound)
  local was = hoverWas[id]
  hoverWas[id] = hovered
  if hovered and not was and sound then
    Foley.play(sound)
  end
end

--- opts: id, label, onClick, width, height, active(bool),
---       hoverSound (cue name or false to silence, default "hover"),
---       clickSound (cue name or false to silence, default "press")
function Widgets.button(opts)
  local id = opts.id
  Clay.element({
    id = id,
    layout = {
      sizing = { width = opts.width or "fit", height = opts.height or Clay.sizing.fixed(34) },
      padding = { x = 14, y = 8 },
      childAlignment = { x = "center", y = "center" },
    },
    backgroundColor = opts.active and Widgets.palette.pink
      or (Clay.pointerOver(id) and Widgets.palette.panel2 or Widgets.palette.panel),
    cornerRadius = 6,
    border = { width = 1, color = Widgets.palette.border },
  }, function()
    local hovered = Clay.pointerOver(id)
    if opts.hoverSound ~= false then
      fireOnEnter(id, hovered, opts.hoverSound or "hover")
    end

    local ps = Clay.getPointerState()
    if hovered and ps.state == "pressedThisFrame" then
      if opts.clickSound ~= false then
        Foley.play(opts.clickSound or "press")
      end
      if opts.onClick then opts.onClick() end
    end

    Clay.text(opts.label, { color = opts.active and { 1, 1, 1 } or Widgets.palette.text })
  end)
end

--- opts: id, label, value(bool), onChange(fn(newValue)). Returns the
--- (possibly flipped) value -- store it back into your own state.
function Widgets.toggle(opts)
  local id = opts.id
  local on = opts.value

  Clay.element({
    id = id,
    layout = {
      sizing = { height = Clay.sizing.fixed(34) },
      padding = { x = 14, y = 8 },
      childGap = 10,
      childAlignment = { x = "left", y = "center" },
    },
    backgroundColor = Clay.pointerOver(id) and Widgets.palette.panel2 or Widgets.palette.panel,
    cornerRadius = 6,
    border = { width = 1, color = Widgets.palette.border },
  }, function()
    local hovered = Clay.pointerOver(id)
    fireOnEnter(id, hovered, "hover")

    local ps = Clay.getPointerState()
    if hovered and ps.state == "pressedThisFrame" then
      on = not on
      Foley.play(on and "on" or "off")
      if opts.onChange then opts.onChange(on) end
    end

    Clay.element({
      id = id .. ":track",
      layout = {
        sizing = { width = Clay.sizing.fixed(36), height = Clay.sizing.fixed(20) },
        padding = 2,
        childAlignment = { x = on and "right" or "left", y = "center" },
      },
      backgroundColor = on and Widgets.palette.mint or Widgets.palette.border,
      cornerRadius = 10,
    }, function()
      Clay.element({
        layout = { sizing = { width = Clay.sizing.fixed(16), height = Clay.sizing.fixed(16) } },
        backgroundColor = { 1, 1, 1 },
        cornerRadius = 8,
      })
    end)

    Clay.text(opts.label, { color = Widgets.palette.text })
  end)

  return on
end

-- Only one slider drags at a time, tracked globally so a drag started over
-- the track keeps updating even if the pointer slips outside it.
local dragId = nil

--- opts: id, label, value, min, max, step, width. Returns the (possibly
--- updated) value -- store it back into your own state.
function Widgets.slider(opts)
  local id = opts.id
  local trackId = id .. ":track"
  local value = opts.value

  local ps = Clay.getPointerState()
  local isOver = Clay.pointerOver(trackId)

  if isOver and ps.state == "pressedThisFrame" then
    dragId = id
  end
  if dragId == id then
    if ps.state == "pressed" or ps.state == "pressedThisFrame" then
      local data = Clay.getElementData(trackId)
      if data.found and data.width > 0 then
        local t = (ps.x - data.x) / data.width
        t = math.max(0, math.min(1, t))
        local raw = opts.min + t * (opts.max - opts.min)
        if opts.step and opts.step > 0 then
          raw = math.floor(raw / opts.step + 0.5) * opts.step
        end
        value = math.max(opts.min, math.min(opts.max, raw))
      end
    else
      dragId = nil
    end
  end

  Clay.element({
    id = id,
    layout = { direction = "column", sizing = { width = opts.width or "grow" }, childGap = 4 },
  }, function()
    Clay.text(opts.label or "", { color = Widgets.palette.textDim, fontSize = 12 })
    Clay.element({
      id = trackId,
      layout = {
        sizing = { width = "grow", height = Clay.sizing.fixed(16) },
        padding = 2,
        childAlignment = { y = "center" },
      },
      backgroundColor = Widgets.palette.panel2,
      cornerRadius = 8,
    }, function()
      local t = 0
      if opts.max > opts.min then
        t = math.max(0, math.min(1, (value - opts.min) / (opts.max - opts.min)))
      end
      Clay.element({
        layout = { sizing = { width = Clay.sizing.percent(t), height = Clay.sizing.fixed(12) } },
        backgroundColor = Widgets.palette.pink,
        cornerRadius = 6,
      })
    end)
  end)

  return value
end

--- A framed card. config: id, layout, backgroundColor, cornerRadius, border, clip.
function Widgets.panel(config, children)
  config = config or {}
  Clay.element({
    id = config.id,
    layout = config.layout or {
      direction = "column", childGap = 10, padding = 14, sizing = { width = "grow" },
    },
    backgroundColor = config.backgroundColor or Widgets.palette.panel,
    cornerRadius = config.cornerRadius or 10,
    border = config.border or { width = 1, color = Widgets.palette.border },
    clip = config.clip,
  }, children)
end

--- A monospace-ish key/value readout card. rows is an array of pre-formatted strings.
function Widgets.readout(title, rows)
  Widgets.panel({}, function()
    if title then
      Clay.text(title, { color = Widgets.palette.mint, fontSize = 13 })
    end
    for _, row in ipairs(rows) do
      Clay.text(row, { color = Widgets.palette.text, fontSize = 13, wrapMode = "none" })
    end
  end)
end

--- opts: id, items = { {key, label}, ... }, active(key), onSelect(fn(key)).
function Widgets.sectionTabBar(opts)
  Clay.element({
    id = opts.id,
    layout = { sizing = { width = "grow" }, childGap = 6, padding = 6 },
    backgroundColor = Widgets.palette.panel,
    cornerRadius = 8,
    clip = { horizontal = true },
  }, function()
    for _, item in ipairs(opts.items) do
      Widgets.button({
        id = opts.id .. ":" .. item.key,
        label = item.label,
        active = opts.active == item.key,
        hoverSound = "tick",
        clickSound = "switch",
        onClick = function()
          if opts.onSelect then opts.onSelect(item.key) end
        end,
      })
    end
  end)
end

return Widgets
