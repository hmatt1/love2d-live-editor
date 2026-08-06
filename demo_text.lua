-- demo_text.lua
-- Showcases Clay text/fonts: registerFont (object + function-source forms),
-- wrapMode, alignment, and lineHeight.

local Clay = require("clay")
local Widgets = require("ui_widgets")

local M = {}

local state = {
  wrapMode = "words",
  alignment = "left",
  lineHeight = 0,
  fontSize = 26,
}

local WRAPS = { "words", "newlines", "none" }
local ALIGNS = { "left", "center", "right" }

local SAMPLE_WORDS =
  "Clay lays out this paragraph for you -- resize the window or drag the sliders "
  .. "below and watch it re-wrap, re-align, and re-measure on every single frame."
local SAMPLE_LINES =
  "Line one\nLine two\nLine three -- wrapMode=\"newlines\" only breaks at these\ncharacters, never mid-word."

function M.declare()
  Widgets.panel({
    layout = { direction = "column", childGap = 14, padding = 16, sizing = { width = "grow", height = "grow" } },
  }, function()
    Clay.text("Text & Fonts -- registerFont, wrapMode, alignment, lineHeight",
      { fontId = "title", color = Widgets.palette.text })

    Clay.element({ id = "text:controls", layout = { childGap = 10, sizing = { width = "grow" } }, clip = { horizontal = true } }, function()
      for _, w in ipairs(WRAPS) do
        Widgets.button({
          id = "text:wrap:" .. w, label = "wrap:" .. w, active = state.wrapMode == w,
          onClick = function() state.wrapMode = w end,
        })
      end
      for _, a in ipairs(ALIGNS) do
        Widgets.button({
          id = "text:align:" .. a, label = "align:" .. a, active = state.alignment == a,
          onClick = function() state.alignment = a end,
        })
      end
    end)

    Clay.element({ layout = { childGap = 24, sizing = { width = "grow" } } }, function()
      state.fontSize = Widgets.slider({
        id = "text:size", label = "fontSize (function-registered \"display\" font): " .. state.fontSize,
        value = state.fontSize, min = 14, max = 48, step = 1,
      })
      state.lineHeight = Widgets.slider({
        id = "text:lh", label = "lineHeight (0 = natural): " .. state.lineHeight,
        value = state.lineHeight, min = 0, max = 60, step = 2,
      })
    end)

    Widgets.panel({
      layout = { sizing = { width = "grow", height = Clay.sizing.fixed(170) }, padding = 16 },
      backgroundColor = Widgets.palette.panel2,
      clip = { vertical = true, horizontal = state.wrapMode ~= "words" },
    }, function()
      Clay.text(state.wrapMode == "newlines" and SAMPLE_LINES or SAMPLE_WORDS, {
        fontId = "display",
        fontSize = state.fontSize,
        wrapMode = state.wrapMode,
        alignment = state.alignment,
        lineHeight = state.lineHeight,
        color = Widgets.palette.text,
      })
    end)

    Clay.text(
      "Registered as Font objects: \"default\" (15px) and \"title\" (20px). Registered as a "
      .. "function: \"display\" (love.graphics.newFont(size), re-measured at whatever fontSize "
      .. "is requested -- try the slider above). Clay also supports registering by file path, "
      .. "e.g. Clay.registerFont(\"body\", \"fonts/Inter.ttf\") -- omitted here since this demo "
      .. "ships no font files.",
      { color = Widgets.palette.textDim, fontSize = 12 }
    )
  end)
end

return M
