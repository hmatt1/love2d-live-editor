-- main.lua
-- An interactive tour of everything clay.lua (UI layout) and foley.lua
-- (procedural UI sound) can do. Switch sections with the tab bar up top.

local Clay = require("clay")
local Widgets = require("ui_widgets")

local SECTIONS = {
  { key = "layout",      label = "Layout",       module = require("demo_layout") },
  { key = "text",        label = "Text & Fonts", module = require("demo_text") },
  { key = "style",       label = "Style",        module = require("demo_style") },
  { key = "scroll",      label = "Scroll",       module = require("demo_scroll") },
  { key = "interact",    label = "Interact",     module = require("demo_interact") },
  { key = "floating",    label = "Floating",     module = require("demo_floating") },
  { key = "soundboard",  label = "Sound Board",  module = require("demo_soundboard") },
  { key = "sounddesign", label = "Sound Design", module = require("demo_sounddesign") },
}

local activeKey = SECTIONS[1].key
local wheelX, wheelY = 0, 0

function love.load()
  love.graphics.setBackgroundColor(Widgets.palette.bg[1], Widgets.palette.bg[2], Widgets.palette.bg[3])

  Clay.initialize(love.graphics.getDimensions())
  Clay.registerFont("default", love.graphics.newFont(15))
  Clay.registerFont("title", love.graphics.newFont(20))
  Clay.registerFont("display", function(size) return love.graphics.newFont(size) end)
end

function love.resize(w, h)
  Clay.setLayoutDimensions(w, h)
end

function love.wheelmoved(dx, dy)
  wheelX = wheelX + dx
  wheelY = wheelY + dy
end

function love.update(dt)
  Clay.setPointerState(love.mouse.getX(), love.mouse.getY(), love.mouse.isDown(1))
  Clay.updateScrollContainers(true, wheelX, wheelY, dt)
  wheelX, wheelY = 0, 0
end

function love.draw()
  Clay.beginLayout()

  Clay.element({
    id = "Root",
    layout = {
      direction = "column",
      sizing = { width = "grow", height = "grow" },
      padding = 14,
      childGap = 14,
    },
    backgroundColor = Widgets.palette.bg,
  }, function()

    Clay.text("clay.lua + foley.lua -- feature tour", { fontId = "title", color = Widgets.palette.text })

    Widgets.sectionTabBar({
      id = "MainTabs",
      items = SECTIONS,
      active = activeKey,
      onSelect = function(key) activeKey = key end,
    })

    for _, section in ipairs(SECTIONS) do
      if section.key == activeKey then
        section.module.declare()
      end
    end
  end)

  Clay.render(Clay.endLayout())
end
