-- demo_floating.lua
-- Showcases Clay floating elements: attachTo "parent" / "root" /
-- "elementWithId", attachPoints, offset, zIndex, pointerCaptureMode,
-- clipTo = "attachedParent", and using getElementData to position one
-- floating element relative to another element's previous-frame box.

local Clay = require("clay")
local Widgets = require("ui_widgets")

local M = {}

local state = { dropdownOpen = false, dropdownChoice = "Alpha" }
local DROPDOWN_ITEMS = { "Alpha", "Bravo", "Charlie", "Delta" }

function M.declare()
  Widgets.panel({
    layout = { direction = "column", childGap = 20, padding = 16, sizing = { width = "grow", height = "grow" } },
  }, function()
    Clay.text("Floating -- attachTo, attachPoints, zIndex, pointerCaptureMode, clipTo",
      { fontId = "title", color = Widgets.palette.text })

    Clay.element({ id = "floating:row", layout = { childGap = 24, sizing = { width = "grow" } }, clip = { horizontal = true } }, function()

      -- Tooltip: attachTo = "parent"
      Clay.element({
        id = "floating:tipAnchor",
        layout = {
          sizing = { width = Clay.sizing.fixed(160), height = Clay.sizing.fixed(60) },
          childAlignment = { x = "center", y = "center" },
        },
        backgroundColor = Widgets.palette.panel2,
        cornerRadius = 8,
      }, function()
        Clay.text("Hover: tooltip\n(attachTo=parent)", { color = Widgets.palette.text, alignment = "center", wrapMode = "newlines", fontSize = 12 })

        if Clay.pointerOver("floating:tipAnchor") then
          Clay.element({
            id = "floating:tooltip",
            floating = {
              attachTo = "parent",
              attachPoints = { element = "centerTop", parent = "centerBottom" },
              offset = { x = 0, y = 8 },
              zIndex = 100,
              pointerCaptureMode = "passthrough",
            },
            layout = { padding = 10 },
            backgroundColor = Widgets.palette.pink,
            cornerRadius = 6,
          }, function()
            Clay.text("I'm floating, attached to my parent", { color = { 1, 1, 1 }, fontSize = 12, wrapMode = "none" })
          end)
        end
      end)

      -- Badge: attachTo = "elementWithId", anchored to the tooltip box above
      -- (declared as a sibling *after* it, since the target must already be
      -- in this frame's element data).
      Clay.element({
        id = "floating:badge",
        floating = {
          attachTo = "elementWithId",
          parentId = "floating:tipAnchor",
          attachPoints = { element = "leftBottom", parent = "rightTop" },
          offset = { x = -6, y = 6 },
          zIndex = 101,
          pointerCaptureMode = "passthrough",
        },
        layout = { sizing = { width = Clay.sizing.fixed(20), height = Clay.sizing.fixed(20) }, childAlignment = { x = "center", y = "center" } },
        backgroundColor = Widgets.palette.mint,
        cornerRadius = 10,
      }, function()
        Clay.text("!", { color = { 0, 0, 0 }, fontSize = 12 })
      end)

      -- Dropdown: attachTo = "root", pointerCaptureMode = "capture"
      Clay.element({
        id = "floating:dropdownAnchor",
        layout = { direction = "column", sizing = { width = Clay.sizing.fixed(200) } },
      }, function()
        Widgets.button({
          id = "floating:dropdownBtn",
          label = "Dropdown: " .. state.dropdownChoice,
          active = state.dropdownOpen,
          onClick = function() state.dropdownOpen = not state.dropdownOpen end,
        })

        if state.dropdownOpen then
          local anchor = Clay.getElementData("floating:dropdownAnchor")
          Clay.element({
            id = "floating:dropdownMenu",
            floating = {
              attachTo = "root",
              attachPoints = { element = "leftTop", parent = "leftTop" },
              offset = { x = anchor.x, y = anchor.y + anchor.height + 4 },
              zIndex = 200,
              pointerCaptureMode = "capture",
            },
            layout = { direction = "column", sizing = { width = Clay.sizing.fixed(200) }, padding = 6, childGap = 4 },
            backgroundColor = Widgets.palette.panel2,
            cornerRadius = 8,
            border = { width = 1, color = Widgets.palette.border },
          }, function()
            for _, item in ipairs(DROPDOWN_ITEMS) do
              Widgets.button({
                id = "floating:item:" .. item, label = item, width = "grow", clickSound = "latch",
                onClick = function()
                  state.dropdownChoice = item
                  state.dropdownOpen = false
                end,
              })
            end
          end)
        end
      end)
    end)

    -- clipTo = "attachedParent": a floating menu that clips to a scroll box.
    Clay.element({ layout = { direction = "column", childGap = 8, sizing = { width = "grow" } } }, function()
      Clay.text("clipTo=\"attachedParent\": this floating panel is clipped to the scroll box below",
        { color = Widgets.palette.textDim, fontSize = 12 })
      Clay.element({
        id = "floating:clipHost",
        layout = { direction = "column", sizing = { width = Clay.sizing.fixed(260), height = Clay.sizing.fixed(90) }, padding = 8 },
        backgroundColor = Widgets.palette.panel2,
        cornerRadius = 8,
        clip = { vertical = true },
      }, function()
        Clay.element({
          floating = {
            attachTo = "parent",
            attachPoints = { element = "leftTop", parent = "leftTop" },
            offset = { x = 20, y = 20 },
            clipTo = "attachedParent",
            zIndex = 5,
            pointerCaptureMode = "passthrough",
          },
          layout = { sizing = { width = Clay.sizing.fixed(220), height = Clay.sizing.fixed(220) }, padding = 10 },
          backgroundColor = Widgets.palette.amber,
          cornerRadius = 8,
        }, function()
          Clay.text("This box is bigger than its host and gets clipped to it.",
            { color = { 0, 0, 0 }, fontSize = 12 })
        end)
      end)
    end)
  end)
end

return M
