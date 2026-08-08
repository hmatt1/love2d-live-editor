# clay.lua

A pure Lua port of [Clay](https://github.com/nicbarker/clay) (v0.14) for LÖVE2D. Single file, no dependencies beyond LÖVE. Handles layout, text, scrolling, floating elements, borders, and rendering.

---

## Setup

```lua
local Clay = require("clay")

local wheelY = 0

function love.load()
    Clay.initialize(love.graphics.getDimensions())
    Clay.registerFont("default", love.graphics.newFont(16))
    Clay.registerFont("title", love.graphics.newFont(24))
end

function love.resize(w, h)
    Clay.setLayoutDimensions(w, h)
end

function love.wheelmoved(dx, dy)
    wheelY = wheelY + dy
end

function love.update(dt)
    -- Call these three every frame, in this order
    Clay.setPointerState(love.mouse.getX(), love.mouse.getY(), love.mouse.isDown(1))
    Clay.updateScrollContainers(false, 0, wheelY, dt)
    wheelY = 0
end

function love.draw()
    Clay.beginLayout()
    -- ... declare your elements here ...
    Clay.render(Clay.endLayout())
end
```

**Call order per frame:** `setPointerState` → `updateScrollContainers` → `beginLayout` → element declarations → `endLayout` → `render`

---

## Elements

Every piece of UI is an element. Elements are declared with `Clay.element(config, children)` where `children` is an optional function that declares child elements.

```lua
Clay.element({
    id = "MyPanel",
    layout = {
        sizing = { width = "grow", height = Clay.sizing.fixed(100) },
        padding = 16,
        childGap = 8,
        direction = "column",
    },
    backgroundColor = { 0.2, 0.2, 0.25 },
    cornerRadius = 8,
}, function()
    Clay.text("Hello", { color = { 1, 1, 1 } })
end)
```

An element with no children function is a leaf (e.g., a plain colored rectangle).

---

## Layout

All layout config goes in the `layout` table.

### Direction

```lua
direction = "column"   -- children stack top-to-bottom (default: row / left-to-right)
direction = "row"      -- children sit left-to-right
```

Aliases: `"topToBottom"` = column, `"leftToRight"` = row.

### Sizing

```lua
sizing = {
    width  = "grow",                    -- fill available space
    height = "fit",                     -- shrink to fit children (default)
    width  = Clay.sizing.fixed(120),    -- exact pixels
    height = Clay.sizing.percent(0.5),  -- 50% of parent
    width  = Clay.sizing.grow(100, 400),  -- grow, but clamp between 100 and 400px
    height = Clay.sizing.fit(80),         -- fit children, minimum 80px
}
```

Shorthand: a bare number is treated as `fixed`. The strings `"grow"` and `"fit"` work directly.

### Padding

```lua
padding = 16                        -- all sides
padding = { x = 12, y = 8 }        -- horizontal / vertical
padding = { left = 8, right = 8, top = 4, bottom = 4 }
```

### Child gap and alignment

```lua
childGap = 12                                    -- space between children
childAlignment = { x = "center", y = "center" } -- "left"/"center"/"right", "top"/"center"/"bottom"
```

---

## Text

```lua
Clay.text("Hello world", {
    color     = { 1, 1, 1 },        -- required
    fontId    = "title",             -- registered font id (default: "default")
    fontSize  = 20,                  -- only used if font was registered as a path or function
    wrapMode  = "words",             -- "words" (default), "newlines", "none"
    alignment = "center",            -- "left" (default), "center", "right"
    lineHeight = 28,                 -- 0 = natural (default)
})
```

Text wraps automatically to the containing element's width. Use `wrapMode = "none"` to prevent wrapping.

---

## Fonts

Register fonts before use. Three source types are accepted:

```lua
-- Prebuilt Font object (fontSize in text config is ignored)
Clay.registerFont("default", love.graphics.newFont(16))

-- File path (Clay loads at the requested fontSize)
Clay.registerFont("body", "fonts/Inter.ttf")

-- Function (called with the requested fontSize)
Clay.registerFont("mono", function(size) return love.graphics.newFont("mono.ttf", size) end)
```

---

## Colors

All colors are LÖVE-style `{ r, g, b }` or `{ r, g, b, a }` tables with values in `0..1`. Alpha defaults to 1.

```lua
backgroundColor = { 0.2, 0.4, 0.8 }       -- opaque blue
backgroundColor = { 0.1, 0.1, 0.1, 0.5 }  -- semi-transparent dark
```

---

## Visual properties

```lua
Clay.element({
    backgroundColor = { 0.2, 0.3, 0.5 },
    cornerRadius    = 12,                    -- uniform, or per-corner:
    cornerRadius    = { topLeft = 12, topRight = 12, bottomLeft = 0, bottomRight = 0 },
    border = {
        width = 2,                           -- uniform width
        color = { 1, 1, 1, 0.3 },
    },
    border = {
        width = { left = 0, right = 0, top = 0, bottom = 2, betweenChildren = 1 },
        color = { 0.4, 0.4, 0.4, 1 },
    },
    overlayColor = { 0, 0, 0, 0.4 },        -- tint drawn over all children
    aspectRatio  = 1.0,                      -- width:height ratio (fixes one axis from the other)
    image        = myLoveImage,              -- love.graphics Image object
})
```

---

## Scroll containers

Give an element a `clip` config. Clay tracks the scroll state internally and applies it automatically.

```lua
Clay.element({
    id = "MyList",
    layout = {
        direction = "column",
        sizing = { width = "grow", height = "grow" },
        padding = 8,
        childGap = 4,
    },
    clip = { vertical = true },   -- enables vertical scrolling/clipping
    -- clip = { horizontal = true, vertical = true }  -- both axes
}, function()
    for i = 1, 100 do
        Clay.element({ layout = { sizing = { width = "grow", height = Clay.sizing.fixed(60) } },
                       backgroundColor = { 0.2, 0.3, 0.4 } })
    end
end)
```

Enable drag scrolling and wheel scrolling in `love.update`:

```lua
function love.update(dt)
    Clay.setPointerState(pointerX, pointerY, pointerDown)
    Clay.updateScrollContainers(
        true,    -- enableDragScrolling
        wheelX,  -- horizontal wheel delta
        wheelY,  -- vertical wheel delta
        dt
    )
    wheelY = 0
end
```

**Important:** only one scroll container should claim the pointer at a time. If you nest elements with `clip`, the **outermost** clipped element wins. Keep only the innermost list as a scroll container — outer containers should not have `clip` unless they also need independent scrolling.

### Reading scroll state

```lua
local ss = Clay.getScrollState("MyList")
if ss then
    -- ss.scrollY       — current scroll offset (negative, 0 = top)
    -- ss.contentHeight — total height of all children
    -- ss.elementHeight — visible height of the scroll container
    local maxScroll = ss.contentHeight - ss.elementHeight
end
```

`Clay.getScrollContainerData("MyList")` returns the raw mutable scroll table — you can write `scrollX`/`scrollY` directly to jump the scroll position programmatically.

---

## Pointer interaction

```lua
-- Check if the pointer is currently over an element (uses previous frame's bounding box)
if Clay.pointerOver("MyButton") then
    -- highlight it
end

-- Conditional styling in-declaration:
backgroundColor = Clay.pointerOver("MyButton") and { 0.4, 0.5, 0.9 } or { 0.2, 0.3, 0.7 }
```

For touch input, drive `setPointerState` from touch callbacks:

```lua
local pointerX, pointerY, pointerDown = 0, 0, false

function love.touchpressed(id, x, y, ...)
    pointerX, pointerY, pointerDown = x, y, true
    Clay.setPointerState(x, y, true)
    -- handle taps here (pointerOver is accurate at this point)
end
function love.touchmoved(id, x, y, ...)  pointerX, pointerY = x, y end
function love.touchreleased(id, x, y, ...)  pointerX, pointerY, pointerDown = x, y, false end
```

`setPointerState` must be called once per frame in `love.update` to drive drag scroll momentum and hover states — the calls in touch callbacks are just for immediate tap detection.

### iOS / high-DPI note

When running on iOS with `usedpiscale = true`, touch coordinates are in **physical pixels**. Pass them directly to Clay — initialize Clay with `love.graphics.getDimensions()` (which also returns physical pixels in that mode) so everything is on the same coordinate system.

---

## Floating elements

Floating elements are positioned relative to a parent or the root, rendered on top at a given z-index, and optionally capture pointer input.

```lua
Clay.element({ id = "Anchor", ... }, function()
    -- declare content...

    if showTooltip then
        Clay.element({
            id = "Tooltip",
            floating = {
                attachTo     = "parent",         -- "parent", "root", "elementWithId"
                parentId     = "SomeOtherId",    -- only for attachTo = "elementWithId"
                attachPoints = {
                    element = "centerBottom",    -- which point on THIS element anchors
                    parent  = "centerTop",       -- to which point on the PARENT
                },
                offset = { x = 0, y = -8 },     -- pixel nudge after attachment
                expand = { width = 0, height = 0 }, -- grow the hit/render box outward
                zIndex = 100,
                pointerCaptureMode = "capture",  -- "capture" (block below) or "passthrough"
                clipTo = "none",                 -- "none" or "attachedParent"
            },
            layout = { padding = 12 },
            backgroundColor = { 0.1, 0.1, 0.1, 0.9 },
            cornerRadius = 6,
        }, function()
            Clay.text("I am a tooltip", { color = { 1, 1, 1 } })
        end)
    end
end)
```

**Attach points** use compass-style strings: `"leftTop"`, `"centerTop"`, `"rightTop"`, `"leftCenter"`, `"centerCenter"`, `"rightCenter"`, `"leftBottom"`, `"centerBottom"`, `"rightBottom"`.

---

## Element bounding box

```lua
local data = Clay.getElementData("MyElement")
if data.found then
    -- data.x, data.y, data.width, data.height (from previous frame)
end
```

Useful for positioning floating elements relative to their anchor's screen coordinates.

---

## Initialization options

```lua
Clay.initialize(width, height, {
    culling               = true,   -- skip offscreen elements (default true)
    maxMeasureCacheEntries = 4096,  -- text measure cache size
    errorHandler          = function(msg) print(msg) end,
})
```

---

## Full frame skeleton

```lua
function love.draw()
    Clay.beginLayout()

    Clay.element({
        id = "Root",
        layout = {
            sizing = { width = "grow", height = "grow" },
            direction = "column",
            padding = 16,
            childGap = 12,
        },
        backgroundColor = { 0.1, 0.1, 0.12 },
    }, function()

        Clay.text("Title", { fontId = "title", color = { 1, 1, 1 } })

        Clay.element({
            id = "ScrollArea",
            layout = {
                sizing = { width = "grow", height = "grow" },
                direction = "column",
                childGap = 8,
                padding = 8,
            },
            clip = { vertical = true },
        }, function()
            for i = 1, 50 do
                Clay.element({
                    layout = { sizing = { width = "grow", height = Clay.sizing.fixed(60) } },
                    backgroundColor = { 0.2, 0.3, 0.4 },
                    cornerRadius = 6,
                }, function()
                    Clay.text("Row " .. i, { color = { 1, 1, 1 } })
                end)
            end
        end)

    end)

    Clay.render(Clay.endLayout())
end
```

---

## Common pitfalls

**Duplicate IDs** — Clay prints a warning and may produce wrong layout. Every element that needs an id must have a unique one per frame. Anonymous elements (no `id`) get stable auto-ids from their parent id and child index.

**Scroll container priority** — only one scroll container scrolls per drag. Clay selects the last container in its internal list whose bounding box contains the pointer. Containers are added in element-close order (inner before outer), so the outermost clipped element wins. If your list isn't scrolling, check that no ancestor element also has `clip` set.

**`setPointerState` timing** — call it in `love.update` every frame, not only in touch/mouse callbacks. The update call drives momentum decay and hover state; omitting it causes momentum to never wind down and `pointerOver` to become stale.

**Scroll container nesting** — `clip` on a parent does not automatically clip its clip-children. Each element with `clip` is independent. A floating dropdown that visually sits inside a scroll container won't be clipped to it unless you set `clipTo = "attachedParent"` on the floating config.

**Physical vs logical pixels on iOS** — `usedpiscale = true` in `love.window.setMode` makes all coordinates physical. Initialize Clay with `love.graphics.getDimensions()` (physical) and pass raw touch coordinates straight through. Do not divide by `love.window.getDPIScale()`.
