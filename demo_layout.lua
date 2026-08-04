-- demo_layout.lua
-- Showcases Clay layout: direction, all four sizing modes, padding, childGap,
-- and childAlignment, all live-adjustable.

local Clay = require("clay")
local Widgets = require("ui_widgets")

local M = {}

local state = {
  direction = "row",
  sizeMode = "grow",
  alignX = "left",
  alignY = "top",
  padding = 16,
  gap = 12,
}

local DIRECTIONS = { "row", "column" }
local SIZE_MODES = { "fixed", "grow", "fit", "percent" }
local ALIGN_X = { "left", "center", "right" }
local ALIGN_Y = { "top", "center", "bottom" }
local LABELS = { "One", "Two Two", "Three Three Three" }
local PERCENTS = { 0.2, 0.3, 0.5 }
local COLORS = { Widgets.palette.pink, Widgets.palette.amber, Widgets.palette.mint }

local function childSizing(i, mode, isRow)
  local along
  if mode == "fixed" then
    along = Clay.sizing.fixed(60 + i * 20)
  elseif mode == "grow" then
    along = "grow"
  elseif mode == "fit" then
    along = "fit"
  else -- percent
    along = Clay.sizing.percent(PERCENTS[i])
  end
  if isRow then
    return { width = along, height = "grow" }
  else
    return { width = "grow", height = along }
  end
end

function M.declare()
  Widgets.panel({
    layout = { direction = "column", childGap = 14, padding = 16, sizing = { width = "grow", height = "grow" } },
  }, function()
    Clay.text("Layout -- direction, sizing, padding, childGap, childAlignment",
      { fontId = "title", color = Widgets.palette.text })

    Clay.element({ id = "layout:row1", layout = { childGap = 10, sizing = { width = "grow" } }, clip = { horizontal = true } }, function()
      Widgets.button({
        id = "layout:dir", label = "direction: " .. state.direction,
        onClick = function() state.direction = (state.direction == "row") and "column" or "row" end,
      })
      for _, m in ipairs(SIZE_MODES) do
        Widgets.button({
          id = "layout:mode:" .. m, label = m, active = state.sizeMode == m,
          onClick = function() state.sizeMode = m end,
        })
      end
    end)

    Clay.element({ id = "layout:row2", layout = { childGap = 10, sizing = { width = "grow" } }, clip = { horizontal = true } }, function()
      for _, a in ipairs(ALIGN_X) do
        Widgets.button({
          id = "layout:ax:" .. a, label = "x:" .. a, active = state.alignX == a,
          onClick = function() state.alignX = a end,
        })
      end
      for _, a in ipairs(ALIGN_Y) do
        Widgets.button({
          id = "layout:ay:" .. a, label = "y:" .. a, active = state.alignY == a,
          onClick = function() state.alignY = a end,
        })
      end
    end)

    Clay.element({ layout = { childGap = 24, sizing = { width = "grow" } } }, function()
      state.padding = Widgets.slider({
        id = "layout:padding", label = "padding: " .. state.padding,
        value = state.padding, min = 0, max = 40, step = 1,
      })
      state.gap = Widgets.slider({
        id = "layout:gap", label = "childGap: " .. state.gap,
        value = state.gap, min = 0, max = 40, step = 1,
      })
    end)

    Clay.element({
      id = "layout:stage",
      layout = {
        direction = state.direction,
        sizing = { width = "grow", height = Clay.sizing.fixed(240) },
        padding = state.padding,
        childGap = state.gap,
        childAlignment = { x = state.alignX, y = state.alignY },
      },
      backgroundColor = Widgets.palette.panel2,
      cornerRadius = 8,
      border = { width = 1, color = Widgets.palette.border },
      clip = { horizontal = true, vertical = true },
    }, function()
      local isRow = state.direction == "row"
      for i = 1, 3 do
        Clay.element({
          id = "layout:box" .. i,
          layout = {
            sizing = childSizing(i, state.sizeMode, isRow),
            padding = 10,
            childAlignment = { x = "center", y = "center" },
          },
          backgroundColor = COLORS[i],
          cornerRadius = 6,
        }, function()
          Clay.text(LABELS[i], { color = { 1, 1, 1 }, wrapMode = "none" })
        end)
      end
    end)
  end)
end

return M
