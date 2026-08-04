-- demo_sounddesign.lua
-- Showcases Foley's live-editing API: getSpec/setSpec/resetSpec/isOverridden,
-- the TONE_PARAMS/NOISE_PARAMS/CLUSTER_PARAMS parameter tables, and
-- getWaveformPoints -- rendered through Clay.setCustomRenderHandler, the one
-- Clay feature with no built-in visual primitive of its own.

local Clay = require("clay")
local Foley = require("foley")
local Widgets = require("ui_widgets")

local M = {}

-- ── custom render handler: draws a bar waveform from a points array ────────
local function waveformRenderHandler(command)
  local points = command.customData and command.customData.points
  if not points or #points == 0 then return end
  local box = command.boundingBox
  local n = #points
  local halfH = box.height * 0.45
  local midY = box.y + box.height / 2
  love.graphics.setColor(Widgets.palette.mint[1], Widgets.palette.mint[2], Widgets.palette.mint[3], 0.9)
  for i, p in ipairs(points) do
    local x = box.x + (i - 0.5) / n * box.width
    love.graphics.line(x, midY - p * halfH, x, midY + p * halfH)
  end
  love.graphics.setColor(1, 1, 1, 1)
end
Clay.setCustomRenderHandler(waveformRenderHandler)

-- ── state ────────────────────────────────────────────────────────────────
local state = { cue = "tick" }
local waveform = {}
local waveformDirty = true

local function paramsFor(layer)
  if layer.kind == "tone" then return Foley.TONE_PARAMS end
  if layer.kind == "noise" then return Foley.NOISE_PARAMS end
  if layer.kind == "cluster" then return Foley.CLUSTER_PARAMS end
  return {}
end

local function fmtParam(p, v)
  if p.fmt:find("%%d") then
    return string.format(p.fmt, math.floor(v + 0.5))
  end
  return string.format(p.fmt, v)
end

local function refreshWaveform()
  waveform = Foley.getWaveformPoints(state.cue, 80)
  waveformDirty = false
end

local function setLayerParam(key, value)
  local spec = Foley.getSpec(state.cue)
  spec[1][key] = value
  Foley.setSpec(state.cue, spec)
  waveformDirty = true
end

function M.declare()
  if waveformDirty then refreshWaveform() end

  Widgets.panel({
    layout = { direction = "column", childGap = 14, padding = 16, sizing = { width = "grow", height = "grow" } },
  }, function()
    Clay.text("Sound Design -- edit a cue live", { fontId = "title", color = Widgets.palette.text })
    Clay.text("getSpec / setSpec / resetSpec / isOverridden / getWaveformPoints",
      { color = Widgets.palette.textDim, fontSize = 12 })

    Clay.element({
      id = "sounddesign:picker",
      layout = { direction = "column", childGap = 6, sizing = { width = "grow" } },
    }, function()
      for _, family in ipairs(Foley.FAMILIES) do
        Clay.element({ id = "sounddesign:row:" .. family.label, layout = { childGap = 6 }, clip = { horizontal = true } }, function()
          for _, cue in ipairs(family.cues) do
            Widgets.button({
              id = "sounddesign:pick:" .. cue, label = cue, active = state.cue == cue,
              hoverSound = "tick", clickSound = false,
              onClick = function() state.cue = cue; waveformDirty = true end,
            })
          end
        end)
      end
    end)

    local spec = Foley.getSpec(state.cue)
    local layer = spec[1]

    Clay.element({ id = "sounddesign:waverow", layout = { childGap = 20, sizing = { width = "grow" } }, clip = { horizontal = true } }, function()
      Clay.element({
        id = "sounddesign:wave",
        layout = { sizing = { width = Clay.sizing.fixed(280), height = Clay.sizing.fixed(120) } },
        backgroundColor = Widgets.palette.panel2,
        cornerRadius = 8,
        custom = { points = waveform },
      })

      Clay.element({ layout = { direction = "column", childGap = 8, sizing = { width = "grow" } } }, function()
        Widgets.button({
          id = "sounddesign:play", label = "Play " .. state.cue, clickSound = false,
          onClick = function() Foley.play(state.cue) end,
        })
        Widgets.button({
          id = "sounddesign:reset",
          label = Foley.isOverridden(state.cue) and "Reset to default (isOverridden)" or "(using built-in default)",
          clickSound = false,
          onClick = function() Foley.resetSpec(state.cue); waveformDirty = true end,
        })
        Clay.text("layer.kind = " .. layer.kind, { color = Widgets.palette.textDim, fontSize = 12 })
      end)
    end)

    Clay.element({
      id = "sounddesign:params",
      layout = { direction = "column", childGap = 10, sizing = { width = "grow" } },
    }, function()
      for _, p in ipairs(paramsFor(layer)) do
        local raw = layer[p.key]
        if p.nullable then
          local enabled = raw ~= nil
          Widgets.toggle({
            id = "sounddesign:enable:" .. p.key, label = p.label .. " enabled", value = enabled,
            onChange = function(v)
              if v then
                setLayerParam(p.key, raw or p.default or p.min)
              else
                setLayerParam(p.key, nil)
              end
            end,
          })
          if enabled then
            local v = Widgets.slider({
              id = "sounddesign:" .. p.key, label = p.label .. ": " .. fmtParam(p, raw),
              value = raw, min = p.min, max = p.max, step = p.step,
            })
            if v ~= raw then setLayerParam(p.key, v) end
          end
        else
          local v0 = raw or p.min
          local v = Widgets.slider({
            id = "sounddesign:" .. p.key, label = p.label .. ": " .. fmtParam(p, v0),
            value = v0, min = p.min, max = p.max, step = p.step,
          })
          if v ~= v0 then setLayerParam(p.key, v) end
        end
      end
    end)
  end)
end

return M
