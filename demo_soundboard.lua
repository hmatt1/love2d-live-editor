-- demo_soundboard.lua
-- Showcases Foley.FAMILIES / Foley.play: every built-in cue, grouped by family,
-- one button each.

local Clay = require("clay")
local Foley = require("foley")
local Widgets = require("ui_widgets")

local M = {}

function M.declare()
  Widgets.panel({
    layout = { direction = "column", childGap = 14, padding = 16, sizing = { width = "grow", height = "grow" } },
  }, function()
    Clay.text("Sound Board -- Foley.FAMILIES x Foley.play(cue)", { fontId = "title", color = Widgets.palette.text })
    
    Clay.element({ layout = { direction = "row", childGap = 12, childAlignment = { y = "center" } } }, function()
      Clay.text(string.format("Master Volume Gain: %.1fx", Foley.masterVolume), { color = Widgets.palette.text })
      Foley.masterVolume = Widgets.slider({
        id = "soundboard:volume",
        value = Foley.masterVolume,
        min = 0.1,
        max = 5.0,
        width = 200,
      })
    end)
    Clay.element({
      id = "soundboard:list",
      layout = { direction = "column", childGap = 14, sizing = { width = "grow", height = "grow" }, padding = { right = 6 } },
      clip = { vertical = true },
    }, function()
      for _, family in ipairs(Foley.FAMILIES) do
        Clay.element({ layout = { direction = "column", childGap = 8 } }, function()
          Clay.text(family.label, { color = Widgets.palette.amber, fontSize = 13 })
          Clay.element({
            id = "soundboard:row:" .. family.label, layout = { childGap = 8, sizing = { width = "grow" } },
            clip = { horizontal = true },
          }, function()
            for _, cue in ipairs(family.cues) do
              Widgets.button({ id = "soundboard:" .. cue, label = cue, clickSound = cue })
            end
          end)
        end)
      end
    end)
  end)
end

return M
