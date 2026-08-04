-- demo_interact.lua
-- Showcases Clay pointer interaction (pointerOver, getPointerState, onHover)
-- wired directly to Foley cues (tick/hover/glide/pop, press/release/tap/thock,
-- on/off/switch/latch) so you can hear each Clay pointer event as it fires.

local Clay = require("clay")
local Foley = require("foley")
local Widgets = require("ui_widgets")

local M = {}

local state = { power = false }
local hoverFrames = { 0, 0, 0, 0 }
local POINTER_CUES = { "tick", "hover", "glide", "pop" }
local PRESS_CUES = { "press", "release", "tap", "thock" }

function M.declare()
  Widgets.panel({
    layout = { direction = "column", childGap = 14, padding = 16, sizing = { width = "grow", height = "grow" } },
  }, function()
    Clay.text("Interact -- pointerOver, getPointerState, onHover + Foley cues",
      { fontId = "title", color = Widgets.palette.text })

    Clay.element({ id = "interact:hoverrow", layout = { childGap = 16, sizing = { width = "grow" } }, clip = { horizontal = true } }, function()
      for i = 1, 4 do
        local id = "interact:hoverbox" .. i
        Clay.element({
          id = id,
          layout = {
            sizing = { width = Clay.sizing.fixed(140), height = Clay.sizing.fixed(80) },
            childAlignment = { x = "center", y = "center" },
          },
          backgroundColor = Clay.pointerOver(id) and Widgets.palette.mint or Widgets.palette.panel2,
          cornerRadius = 8,
        }, function()
          Clay.onHover(function()
            hoverFrames[i] = hoverFrames[i] + 1
          end, i)
          Clay.text("onHover #" .. i .. "\n(" .. hoverFrames[i] .. " frames)",
            { color = { 1, 1, 1 }, alignment = "center", wrapMode = "newlines" })
        end)
      end
    end)

    Clay.text("Pointer family cues (hover + click each button):", { color = Widgets.palette.textDim, fontSize = 12 })
    Clay.element({ id = "interact:pointerrow", layout = { childGap = 10 }, clip = { horizontal = true } }, function()
      for _, cue in ipairs(POINTER_CUES) do
        Widgets.button({ id = "interact:pointer:" .. cue, label = cue, hoverSound = cue, clickSound = cue })
      end
    end)

    Clay.text("Press family cues:", { color = Widgets.palette.textDim, fontSize = 12 })
    Clay.element({ id = "interact:pressrow", layout = { childGap = 10 }, clip = { horizontal = true } }, function()
      for _, cue in ipairs(PRESS_CUES) do
        Widgets.button({ id = "interact:press:" .. cue, label = cue, hoverSound = false, clickSound = cue })
      end
    end)

    state.power = Widgets.toggle({ id = "interact:power", label = "Power (Toggle family: on/off)", value = state.power })

    local ps = Clay.getPointerState()
    Widgets.readout("getPointerState()", {
      string.format("x=%.0f y=%.0f state=%s", ps.x, ps.y, ps.state),
    })
  end)
end

return M
