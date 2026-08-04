-- demo_scroll.lua
-- Showcases Clay scroll containers: clip.vertical / clip.horizontal,
-- getScrollState, getScrollContainerData (incl. writing scrollX/scrollY
-- directly), getScrollOffset, and scrollToTop/scrollToBottom/scrollToEnd.

local Clay = require("clay")
local Widgets = require("ui_widgets")

local M = {}

local VLIST = "scroll:vlist"
local HLIST = "scroll:hlist"

function M.declare()
  Widgets.panel({
    layout = { direction = "column", childGap = 14, padding = 16, sizing = { width = "grow", height = "grow" } },
  }, function()
    Clay.text("Scroll -- clip, getScrollState, scrollToTop/Bottom/End, getScrollOffset",
      { fontId = "title", color = Widgets.palette.text })

    -- Stacked (not side-by-side) so both lists' own clip containers stay the
    -- outermost scrollable thing under the pointer -- wrapping them in a
    -- shared horizontal-clip row would out-rank their own vertical/horizontal
    -- clips for drag scrolling (see clay.md's "Scroll container priority").
    Clay.element({
      id = "scroll:col", layout = { direction = "column", childGap = 16, sizing = { width = "grow", height = "grow" } },
    }, function()

      -- vertical scroll list
      Clay.element({ layout = { direction = "column", childGap = 8, sizing = { width = "grow" } } }, function()
        Clay.element({ id = "scroll:vbuttons", layout = { childGap = 8 }, clip = { horizontal = true } }, function()
          Widgets.button({ id = "scroll:vtop", label = "scrollToTop", onClick = function() Clay.scrollToTop(VLIST) end })
          Widgets.button({ id = "scroll:vbot", label = "scrollToBottom", onClick = function() Clay.scrollToBottom(VLIST) end })
        end)

        Clay.element({
          id = VLIST,
          layout = { direction = "column", sizing = { width = "grow", height = Clay.sizing.fixed(240) }, padding = 6, childGap = 6 },
          backgroundColor = Widgets.palette.panel2,
          cornerRadius = 8,
          clip = { vertical = true },
        }, function()
          for i = 1, 40 do
            Clay.element({
              layout = { sizing = { width = "grow", height = Clay.sizing.fixed(36) }, padding = { x = 10 }, childAlignment = { y = "center" } },
              backgroundColor = (i % 2 == 0) and Widgets.palette.panel or Widgets.palette.panel2,
              cornerRadius = 4,
            }, function()
              Clay.text("row " .. i, { color = Widgets.palette.text, fontSize = 12 })
            end)
          end
        end)

        local ss = Clay.getScrollState(VLIST)
        local off = Clay.getScrollOffset(VLIST)
        Widgets.readout("getScrollState(\"" .. VLIST .. "\")", {
          ss and string.format("scrollY %.0f / max %.0f", -ss.scrollY, math.max(0, ss.contentHeight - ss.elementHeight)) or "n/a",
          string.format("getScrollOffset: x=%.0f y=%.0f", off.x, off.y),
        })
      end)

      -- horizontal scroll list
      Clay.element({ layout = { direction = "column", childGap = 8, sizing = { width = "grow" } } }, function()
        Clay.element({ id = "scroll:hbuttons", layout = { childGap = 8 }, clip = { horizontal = true } }, function()
          Widgets.button({
            id = "scroll:hstart", label = "scrollX = 0 (direct write)",
            onClick = function()
              local sd = Clay.getScrollContainerData(HLIST)
              if sd then sd.scrollX = 0; sd.momentumX = 0 end
            end,
          })
          Widgets.button({ id = "scroll:hend", label = "scrollToEnd", onClick = function() Clay.scrollToEnd(HLIST) end })
        end)

        Clay.element({
          id = HLIST,
          layout = { sizing = { width = "grow", height = Clay.sizing.fixed(90) }, padding = 6, childGap = 6 },
          backgroundColor = Widgets.palette.panel2,
          cornerRadius = 8,
          clip = { horizontal = true },
        }, function()
          for i = 1, 30 do
            Clay.element({
              layout = { sizing = { width = Clay.sizing.fixed(80), height = "grow" }, childAlignment = { x = "center", y = "center" } },
              backgroundColor = Widgets.palette.panel,
              cornerRadius = 4,
            }, function()
              Clay.text(tostring(i), { color = Widgets.palette.text })
            end)
          end
        end)

        local hd = Clay.getScrollContainerData(HLIST)
        Widgets.readout("getScrollContainerData(\"" .. HLIST .. "\")", {
          hd and string.format("scrollX %.0f  contentWidth %.0f", hd.scrollX, hd.contentWidth or 0) or "n/a",
        })
      end)
    end)
  end)
end

return M
