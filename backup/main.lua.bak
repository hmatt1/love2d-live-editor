-- main.lua
-- Pick a library on the main menu, then take an interactive tour of its
-- public API. Switch sections with the tab bar up top; "< Menu" backs out.

local Clay = require("clay")
local Widgets = require("ui_widgets")

local DEMOS = {
  { key = "clay", label = "Clay", subtitle = "UI layout", sections = {
      { key = "layout",   label = "Layout",       module = require("demo_layout") },
      { key = "text",     label = "Text & Fonts", module = require("demo_text") },
      { key = "style",    label = "Style",        module = require("demo_style") },
      { key = "scroll",   label = "Scroll",       module = require("demo_scroll") },
      { key = "interact", label = "Interact",     module = require("demo_interact") },
      { key = "floating", label = "Floating",     module = require("demo_floating") },
  }},
  { key = "foley", label = "Foley", subtitle = "Procedural UI sound", sections = {
      { key = "soundboard",  label = "Sound Board",  module = require("demo_soundboard") },
      { key = "sounddesign", label = "Sound Design", module = require("demo_sounddesign") },
  }},
}

local activeDemo = nil -- nil = show the menu; otherwise a DEMOS[].key
local activeKey = nil   -- section key within the active demo
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

local function findDemo(key)
  for _, demo in ipairs(DEMOS) do
    if demo.key == key then return demo end
  end
end

local function drawMenu()
  Clay.element({
    id = "MenuWrapper",
    layout = { 
      direction = "column", 
      sizing = { width = "grow", height = "grow" }, 
      childAlignment = { x = "center", y = "center" } 
    }
  }, function()
    Clay.element({
      id = "MenuCenter",
      layout = { direction = "column", childGap = 32, sizing = { width = Clay.sizing.fixed(480) } }
    }, function()
      
      -- Header
      Clay.element({ layout = { direction = "column", childGap = 8, childAlignment = { x = "center" } } }, function()
        Clay.text("clay.lua + foley.lua", { fontId = "title", color = Widgets.palette.text })
        Clay.text("Pick a library to explore.", { color = Widgets.palette.textDim })
      end)

      -- Cards
      Clay.element({ id = "MenuCards", layout = { direction = "column", childGap = 16, sizing = { width = "grow" } } }, function()
        for i, demo in ipairs(DEMOS) do
          local accentColor = (i == 1) and Widgets.palette.pink or Widgets.palette.mint
          Widgets.actionCard({
            id = "Card:" .. demo.key,
            title = demo.label,
            subtitle = demo.subtitle,
            accentColor = accentColor,
            onClick = function()
              activeDemo = demo.key
              activeKey = demo.sections[1].key
            end,
          })
        end
      end)
      
    end)
  end)
end

local function drawDemo(demo)
  Clay.element({
    id = "DemoHeader",
    layout = { childGap = 10, sizing = { width = "grow" }, childAlignment = { y = "center" } },
    clip = { horizontal = true },
  }, function()
    Widgets.button({
      id = "Back",
      label = "< Menu",
      hoverSound = "tick",
      clickSound = "switch",
      onClick = function()
        activeDemo = nil
        activeKey = nil
      end,
    })
    Clay.text(demo.label .. " -- feature tour", { fontId = "title", color = Widgets.palette.text })
  end)

  Widgets.sectionTabBar({
    id = "SectionTabs",
    items = demo.sections,
    active = activeKey,
    onSelect = function(key) activeKey = key end,
  })

  for _, section in ipairs(demo.sections) do
    if section.key == activeKey then
      section.module.declare()
    end
  end
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
    local demo = activeDemo and findDemo(activeDemo)
    if demo then
      drawDemo(demo)
    else
      drawMenu()
    end
  end)

  Clay.render(Clay.endLayout())
end
