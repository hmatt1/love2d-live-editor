-- demo_style.lua
-- Showcases Clay visual properties: cornerRadius (uniform + per-corner),
-- border (uniform + per-side + betweenChildren), overlayColor, aspectRatio,
-- and image (a procedurally-drawn canvas, so no binary asset is needed).

local Clay = require("clay")
local Widgets = require("ui_widgets")

local M = {}

local badgeImage

local function getBadgeImage()
  if not badgeImage then
    badgeImage = love.graphics.newCanvas(128, 128)
    love.graphics.push("all")
    love.graphics.setCanvas(badgeImage)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(Widgets.palette.pink)
    love.graphics.circle("fill", 64, 64, 60)
    love.graphics.setColor(Widgets.palette.mint)
    love.graphics.circle("fill", 64, 64, 34)
    love.graphics.setColor(Widgets.palette.amber)
    love.graphics.rectangle("fill", 8, 54, 112, 20)
    love.graphics.setCanvas()
    love.graphics.pop()
  end
  return badgeImage
end

function M.declare()
  Widgets.panel({
    layout = { direction = "column", childGap = 14, padding = 16, sizing = { width = "grow", height = "grow" } },
  }, function()
    Clay.text("Style -- cornerRadius, border, overlayColor, aspectRatio, image",
      { fontId = "title", color = Widgets.palette.text })

    Clay.element({
      id = "style:container", layout = { direction = "column", childGap = 16, sizing = { width = "grow", height = "grow" } },
      clip = { vertical = true, horizontal = true },
    }, function()

      Clay.element({
        id = "style:row1", layout = { childGap = 16, sizing = { width = "grow" }, childAlignment = { y = "top" } },
      }, function()
        -- cornerRadius: uniform vs. per-corner
        Clay.element({
          layout = { direction = "column", childGap = 8, sizing = { width = Clay.sizing.fixed(160) } },
        }, function()
          Clay.text("cornerRadius", { color = Widgets.palette.textDim, fontSize = 12 })
          Clay.element({
            layout = { sizing = { width = "grow", height = Clay.sizing.fixed(70) } },
            backgroundColor = Widgets.palette.pink, cornerRadius = 24,
          })
          Clay.element({
            layout = { sizing = { width = "grow", height = Clay.sizing.fixed(70) } },
            backgroundColor = Widgets.palette.amber,
            cornerRadius = { topLeft = 24, topRight = 0, bottomLeft = 0, bottomRight = 24 },
          })
        end)

        -- border: uniform vs. per-side + betweenChildren
        Clay.element({
          layout = { direction = "column", childGap = 8, sizing = { width = Clay.sizing.fixed(160) } },
        }, function()
          Clay.text("border", { color = Widgets.palette.textDim, fontSize = 12 })
          Clay.element({
            layout = { sizing = { width = "grow", height = Clay.sizing.fixed(70) } },
            backgroundColor = Widgets.palette.panel2,
            border = { width = 2, color = Widgets.palette.mint },
            cornerRadius = 6,
          })
          Clay.element({
            id = "style:betweenChildren",
            layout = {
              direction = "column", sizing = { width = "grow", height = Clay.sizing.fixed(70) },
              padding = 6,
            },
            backgroundColor = Widgets.palette.panel2,
            border = { width = { left = 0, right = 0, top = 0, bottom = 0, betweenChildren = 1 }, color = Widgets.palette.border },
          }, function()
            for i = 1, 3 do
              Clay.element({ layout = { sizing = { width = "grow", height = "grow" } } }, function()
                Clay.text("row " .. i, { color = Widgets.palette.text, fontSize = 11 })
              end)
            end
          end)
        end)
      end)

      Clay.element({
        id = "style:row2", layout = { childGap = 16, sizing = { width = "grow" }, childAlignment = { y = "top" } },
      }, function()
        -- overlayColor: tint drawn over an element's children
        Clay.element({
          layout = { direction = "column", childGap = 8, sizing = { width = Clay.sizing.fixed(160) } },
        }, function()
          Clay.text("overlayColor", { color = Widgets.palette.textDim, fontSize = 12 })
          Clay.element({
            layout = {
              sizing = { width = "grow", height = Clay.sizing.fixed(148) },
              padding = 10, childAlignment = { x = "center", y = "center" },
            },
            backgroundColor = Widgets.palette.mint,
            overlayColor = { 0, 0, 0, 0.55 },
            cornerRadius = 8,
          }, function()
            Clay.text("dimmed by\noverlayColor", { color = { 1, 1, 1 }, alignment = "center", wrapMode = "newlines" })
          end)
        end)

        -- aspectRatio + image
        Clay.element({
          layout = { direction = "column", childGap = 8, sizing = { width = Clay.sizing.fixed(160) } },
        }, function()
          Clay.text("aspectRatio + image", { color = Widgets.palette.textDim, fontSize = 12 })
          Clay.element({
            layout = { sizing = { width = "grow" } },
            image = getBadgeImage(),
            aspectRatio = 1.0,
            cornerRadius = 8,
          })
        end)
      end)

    end)
  end)
end

return M
