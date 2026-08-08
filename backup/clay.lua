--[[----------------------------------------------------------------------------
clay.lua - a pure Lua port of Clay (https://github.com/nicbarker/clay) for LOVE2D.
Ported from clay.h VERSION 0.14. Single file, no dependencies beyond LOVE.

Ported features: fit/grow/fixed/percent sizing with min/max, padding, childGap,
child alignment, row/column layout direction, text measurement + word wrapping +
text alignment, images, aspect ratio, floating elements (attach points, expand,
zIndex, pointer capture/passthrough, clipTo), clip/scroll containers (wheel +
drag scrolling with momentum), borders (per side + betweenChildren), per-corner
radius, overlay color, offscreen culling, pointer hit testing, onHover, and a
built-in love.graphics renderer.

Not ported: the debug view, transitions/animations, letterSpacing (LOVE has no
cheap per-glyph spacing), external scroll handling, multiple contexts.

Colors are LOVE-style 0..1 tables: { r, g, b, a } (alpha defaults to 1).
Element ids are strings. Elements without an id get a stable anonymous id
derived from their parent id and child index, like clay does.

Basic usage:

    local Clay = require("clay")

    local wheelY = 0
    function love.wheelmoved(dx, dy) wheelY = wheelY + dy end

    function love.load()
      Clay.initialize(love.graphics.getDimensions())
    end

    function love.resize(w, h) Clay.setLayoutDimensions(w, h) end

    function love.update(dt)
      Clay.setPointerState(love.mouse.getX(), love.mouse.getY(), love.mouse.isDown(1))
      Clay.updateScrollContainers(false, 0, wheelY, dt)
      wheelY = 0
    end

    function love.draw()
      Clay.beginLayout()
      Clay.element({
        id = "Root",
        layout = {
          direction = "column",
          sizing = { width = "grow", height = "grow" },
          padding = 16,
          childGap = 16,
        },
        backgroundColor = { 0.13, 0.13, 0.16 },
      }, function()
        Clay.text("Hello from clay.lua", { fontSize = 24, color = { 1, 1, 1 } })
        Clay.element({
          id = "Panel",
          layout = { sizing = { width = "grow", height = Clay.sizing.fixed(120) } },
          backgroundColor = Clay.pointerOver("Panel") and { 0.3, 0.4, 0.6 } or { 0.22, 0.22, 0.28 },
          cornerRadius = 8,
        })
      end)
      Clay.render(Clay.endLayout())
    end

Sizing values accept: a number (fixed pixels), "grow", "fit", or one of
Clay.sizing.fit(min, max) / Clay.sizing.grow(min, max) / Clay.sizing.fixed(px)
/ Clay.sizing.percent(0..1).

Scroll containers: give the element an id and clip = { vertical = true }. The
internal scroll offset is applied automatically (pass clip.childOffset to
override, e.g. for external scroll handling).

Call order per frame: setPointerState -> updateScrollContainers ->
beginLayout -> declarations -> endLayout -> render.

--------------------------------------------------------------------------------
LICENSE (retained from clay.h; this file is an altered, ported version)

zlib/libpng license

Copyright (c) 2024 Nic Barker

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
    claim that you wrote the original software. If you use this software in a
    product, an acknowledgment in the product documentation would be
    appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
    be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source
    distribution.
----------------------------------------------------------------------------]]--

local Clay = {}
Clay._VERSION = "clay.lua 0.1 (ported from clay.h v0.14)"

local max, min, floor = math.max, math.min, math.floor
local HUGE = math.huge
local EPSILON = 0.01
local ROOT_ID = "__clayRoot"
local EMPTY = {}
local WHITE = { 1, 1, 1, 1 }

local ctx = nil

local function floatEqual(a, b)
  local d = a - b
  return d < EPSILON and d > -EPSILON
end

local ATTACH_POINTS = {
  leftTop      = { 0,   0   },
  leftCenter   = { 0,   0.5 },
  leftBottom   = { 0,   1   },
  centerTop    = { 0.5, 0   },
  centerCenter = { 0.5, 0.5 },
  centerBottom = { 0.5, 1   },
  rightTop     = { 1,   0   },
  rightCenter  = { 1,   0.5 },
  rightBottom  = { 1,   1   },
  -- Common aliases for developer convenience
  topLeft      = { 0,   0   },
  topCenter    = { 0.5, 0   },
  topRight     = { 1,   0   },
  center       = { 0.5, 0.5 },
  bottomLeft   = { 0,   1   },
  bottomCenter = { 0.5, 1   },
  bottomRight  = { 1,   1   },
  centerLeft   = { 0,   0.5 },
  centerRight  = { 1,   0.5 },
}

-- ## Sizing constructors ------------------------------------------------------

Clay.sizing = {
  fit = function(minSize, maxSize)
    return { type = "fit", min = minSize or 0, max = maxSize or HUGE }
  end,
  grow = function(minSize, maxSize)
    return { type = "grow", min = minSize or 0, max = maxSize or HUGE }
  end,
  fixed = function(px)
    return { type = "fixed", min = px, max = px }
  end,
  percent = function(p)
    return { type = "percent", percent = p }
  end,
}

-- ## Declaration normalizers --------------------------------------------------
-- User config tables are never mutated; every element gets fresh internal
-- tables so shared config tables between elements are safe.

local function normalizeColor(c)
  if not c then return nil end
  return { c[1] or c.r or 0, c[2] or c.g or 0, c[3] or c.b or 0, c[4] or c.a or 1 }
end

local function normalizeSizingAxis(value)
  if value == nil then
    return { type = "fit", min = 0, max = HUGE }
  end
  local t = type(value)
  if t == "number" then
    return { type = "fixed", min = value, max = value }
  end
  if t == "string" then
    if value == "grow" then return { type = "grow", min = 0, max = HUGE } end
    if value == "fit" then return { type = "fit", min = 0, max = HUGE } end
    error(("clay: unknown sizing keyword %q (expected \"grow\" or \"fit\")"):format(value))
  end
  local kind = value.type or "fit"
  if kind == "percent" then
    -- min/max mirror clay's behavior where percent elements contribute zero
    -- height during the pre-Y-axis fit propagation pass.
    return { type = "percent", percent = value.percent or 0, min = 0, max = 0 }
  end
  local minSize = value.min or 0
  local maxSize = value.max
  if maxSize == nil or maxSize <= 0 then maxSize = HUGE end
  return { type = kind, min = minSize, max = maxSize }
end

local function normalizePadding(p)
  if p == nil then
    return { left = 0, right = 0, top = 0, bottom = 0 }
  end
  if type(p) == "number" then
    return { left = p, right = p, top = p, bottom = p }
  end
  local x, y = p.x or 0, p.y or 0
  return { left = p.left or x, right = p.right or x, top = p.top or y, bottom = p.bottom or y }
end

local function normalizeCornerRadius(c)
  if not c then
    return { topLeft = 0, topRight = 0, bottomLeft = 0, bottomRight = 0 }
  end
  if type(c) == "number" then
    return { topLeft = c, topRight = c, bottomLeft = c, bottomRight = c }
  end
  return {
    topLeft = c.topLeft or 0, topRight = c.topRight or 0,
    bottomLeft = c.bottomLeft or 0, bottomRight = c.bottomRight or 0,
  }
end

local function normalizeLayout(l)
  l = l or EMPTY
  local sizing = l.sizing or EMPTY
  local alignment = l.childAlignment or l.alignment or EMPTY
  local direction = l.layoutDirection or l.direction
  return {
    sizing = {
      width = normalizeSizingAxis(sizing.width),
      height = normalizeSizingAxis(sizing.height),
    },
    padding = normalizePadding(l.padding),
    childGap = l.childGap or 0,
    alignX = alignment.x or "left",
    alignY = alignment.y or "top",
    leftToRight = not (direction == "topToBottom" or direction == "column"),
  }
end

local DEFAULT_LAYOUT = normalizeLayout(nil)

local function normalizeBorder(b)
  if not b then return nil end
  local w = b.width
  local width
  if type(w) == "number" then
    width = { left = w, right = w, top = w, bottom = w, betweenChildren = 0 }
  elseif type(w) == "table" then
    width = {
      left = w.left or 0, right = w.right or 0, top = w.top or 0, bottom = w.bottom or 0,
      betweenChildren = w.betweenChildren or 0,
    }
  else
    return nil
  end
  if width.left == 0 and width.right == 0 and width.top == 0
      and width.bottom == 0 and width.betweenChildren == 0 then
    return nil
  end
  return { color = normalizeColor(b.color) or { 0, 0, 0, 1 }, width = width }
end

local function normalizeFloating(f)
  if not f then return nil end
  local attachTo = f.attachTo or "none"
  if attachTo == "none" then return nil end
  local ap = f.attachPoints or EMPTY
  local elementPoint, parentPoint = ap.element or "leftTop", ap.parent or "leftTop"
  if not ATTACH_POINTS[elementPoint] then elementPoint = "leftTop" end
  if not ATTACH_POINTS[parentPoint]  then parentPoint  = "leftTop" end
  return {
    attachTo = attachTo,
    offset = { x = f.offset and f.offset.x or 0, y = f.offset and f.offset.y or 0 },
    expand = { width = f.expand and f.expand.width or 0, height = f.expand and f.expand.height or 0 },
    parentId = f.parentId,
    zIndex = f.zIndex or 0,
    attachPoints = { element = elementPoint, parent = parentPoint },
    pointerCaptureMode = f.pointerCaptureMode or "capture",
    clipTo = f.clipTo or "none",
  }
end

local function normalizeTextConfig(cfg)
  cfg = cfg or EMPTY
  return {
    color = normalizeColor(cfg.color or cfg.textColor) or WHITE,
    fontId = cfg.fontId or cfg.font or "default",
    fontSize = cfg.fontSize or 16,
    lineHeight = cfg.lineHeight or 0,
    wrapMode = cfg.wrapMode or "words",
    alignment = cfg.alignment or cfg.textAlignment or "left",
    userData = cfg.userData,
  }
end

-- ## Fonts and text measurement -----------------------------------------------

local fontSources = {}
local fontCache = {}
local measureCache = {}
local measureCacheCount = 0
local measureTextOverride = nil

-- source: a .ttf path, a function(size) -> Font, or a prebuilt Font object
-- (prebuilt fonts ignore fontSize).
function Clay.registerFont(fontId, source)
  fontSources[fontId] = source
  fontCache = {}
  Clay.resetMeasureTextCache()
end

local function getFont(fontId, size)
  local key = tostring(fontId) .. "@" .. size
  local font = fontCache[key]
  if not font then
    local source = fontSources[fontId]
    local t = type(source)
    if t == "string" then
      font = love.graphics.newFont(source, size)
    elseif t == "function" then
      font = source(size)
    elseif source ~= nil then
      font = source
    else
      font = love.graphics.newFont(size)
    end
    fontCache[key] = font
  end
  return font
end
Clay.getFont = getFont

-- Override with fn(text, textConfig) -> width, height to measure with
-- something other than LOVE fonts.
function Clay.setMeasureTextFunction(fn)
  measureTextOverride = fn
  Clay.resetMeasureTextCache()
end

function Clay.resetMeasureTextCache()
  measureCache = {}
  measureCacheCount = 0
end

local function measureText(text, config)
  if measureTextOverride then
    return measureTextOverride(text, config)
  end
  local font = getFont(config.fontId, config.fontSize)
  return font:getWidth(text), font:getHeight()
end

-- Port of Clay__MeasureTextCached: splits text into measured words on spaces
-- and newlines. Spaces are folded into the preceding word (width + length),
-- newlines become zero-length marker words. Byte scanning is UTF-8 safe since
-- 0x20/0x0A never appear inside multibyte sequences.
local function measureWords(text, config)
  local key = tostring(config.fontId) .. "@" .. config.fontSize .. "\1" .. text
  local item = measureCache[key]
  if item then
    item.generation = ctx.generation
    return item
  end

  item = {
    words = {}, minWidth = 0, unwrappedWidth = 0, unwrappedHeight = 0,
    containsNewlines = false, generation = ctx.generation,
  }
  local words = item.words
  local spaceWidth = measureText(" ", config)
  local start = 1
  local pos = 1
  local lineWidth = 0
  local measuredWidth = 0
  local len = #text

  while pos <= len do
    local byte = text:byte(pos)
    local isSpace = (byte == 32)
    local isNewline = (byte == 10)
    local isBreakChar = (byte == 45 or byte == 47 or byte == 95 or byte == 46)
    local isLongWord = (pos - start + 1 >= 16)

    if isSpace or isNewline or isBreakChar or isLongWord then
      if isSpace then
        local wordLen = pos - start
        local w, h = 0, 0
        if wordLen > 0 then
          w, h = measureText(text:sub(start, pos - 1), config)
        end
        w = w + spaceWidth
        if w > item.minWidth then item.minWidth = w end
        if h > item.unwrappedHeight then item.unwrappedHeight = h end
        words[#words + 1] = { start = start, length = wordLen + 1, width = w }
        lineWidth = lineWidth + w
        start = pos + 1
      elseif isNewline then
        local wordLen = pos - start
        local w, h = 0, 0
        if wordLen > 0 then
          w, h = measureText(text:sub(start, pos - 1), config)
        end
        if w > item.minWidth then item.minWidth = w end
        if h > item.unwrappedHeight then item.unwrappedHeight = h end
        if wordLen > 0 then
          words[#words + 1] = { start = start, length = wordLen, width = w }
        end
        words[#words + 1] = { start = pos + 1, length = 0, width = 0 }
        lineWidth = lineWidth + w
        if lineWidth > measuredWidth then measuredWidth = lineWidth end
        item.containsNewlines = true
        lineWidth = 0
        start = pos + 1
      else
        local wordLen = pos - start + 1
        local w, h = measureText(text:sub(start, pos), config)
        if w > item.minWidth then item.minWidth = w end
        if h > item.unwrappedHeight then item.unwrappedHeight = h end
        words[#words + 1] = { start = start, length = wordLen, width = w }
        lineWidth = lineWidth + w
        start = pos + 1
      end
    end
    pos = pos + 1
  end
  if start <= len then
    local w, h = measureText(text:sub(start, len), config)
    words[#words + 1] = { start = start, length = len - start + 1, width = w }
    lineWidth = lineWidth + w
    if h > item.unwrappedHeight then item.unwrappedHeight = h end
    if w > item.minWidth then item.minWidth = w end
  end
  if lineWidth > measuredWidth then measuredWidth = lineWidth end
  item.unwrappedWidth = measuredWidth

  if item.unwrappedHeight == 0 then
    local _, spaceH = measureText(" ", config)
    item.unwrappedHeight = spaceH
  end

  measureCache[key] = item
  measureCacheCount = measureCacheCount + 1
  return item
end

-- ## Context and element lifecycle ---------------------------------------------

function Clay.initialize(width, height, options)
  options = options or {}
  if width == nil and love and love.graphics then
    width, height = love.graphics.getDimensions()
  end
  ctx = {
    layoutWidth = width or 0,
    layoutHeight = height or 0,
    generation = 0,
    openStack = {},
    openClipStack = {},
    treeRoots = {},
    renderCommands = {},
    elementData = {},
    scrollContainers = {},
    pointer = { x = 0, y = 0, state = "released" },
    pointerOverIds = {},
    pointerOverSet = {},
    cullingEnabled = options.culling ~= false,
    maxMeasureCacheEntries = options.maxMeasureCacheEntries or 4096,
    errorHandler = options.errorHandler or function(message) print("[clay] " .. message) end,
  }
end

function Clay.setLayoutDimensions(width, height)
  assert(ctx, "clay: call Clay.initialize() before setLayoutDimensions()")
  ctx.layoutWidth = width
  ctx.layoutHeight = height
end

function Clay.setCullingEnabled(enabled)
  ctx.cullingEnabled = enabled
end

local function addElementData(id, element)
  local item = ctx.elementData[id]
  if item then
    if item.generation <= ctx.generation then
      item.generation = ctx.generation + 1
      item.element = element
      item.onHover = nil
      item.onHoverUserData = nil
    else
      ctx.errorHandler("clay: duplicate element id declared this frame: " .. tostring(id))
    end
    return item
  end
  item = {
    id = id, element = element, generation = ctx.generation + 1,
    boundingBox = { x = 0, y = 0, width = 0, height = 0 },
  }
  ctx.elementData[id] = item
  return item
end

local function updateAspectRatioBox(element)
  local ratio = element.aspectRatio or 0
  if ratio ~= 0 then
    if element.width == 0 and element.height ~= 0 then
      element.width = element.height * ratio
    elseif element.width ~= 0 and element.height == 0 then
      element.height = element.width * (1 / ratio)
    end
  end
end

local function applyDeclaration(element, config, parent)
  element.layout = normalizeLayout(config.layout)
  element.backgroundColor = normalizeColor(config.backgroundColor)
  element.overlayColor = normalizeColor(config.overlayColor)
  element.cornerRadius = normalizeCornerRadius(config.cornerRadius)
  element.aspectRatio = config.aspectRatio or 0
  element.image = config.image
  element.custom = config.custom
  element.userData = config.userData
  element.border = normalizeBorder(config.border)

  local sw, sh = element.layout.sizing.width, element.layout.sizing.height
  if (sw.type == "percent" and sw.percent > 1) or (sh.type == "percent" and sh.percent > 1) then
    ctx.errorHandler("clay: sizing percent must be between 0 and 1 (element '" .. element.id .. "')")
  end

  local floating = normalizeFloating(config.floating)
  if floating then
    local clipId = false
    if floating.attachTo == "parent" then
      floating.parentId = parent.id
      clipId = ctx.openClipStack[#ctx.openClipStack] or false
    elseif floating.attachTo == "elementWithId" then
      local target = floating.parentId and ctx.elementData[floating.parentId]
      if target and target.element then
        clipId = target.element.clipId or false
      else
        ctx.errorHandler("clay: floating element '" .. element.id
          .. "' declared parentId '" .. tostring(floating.parentId)
          .. "' but no element with that id was found")
      end
    elseif floating.attachTo == "root" then
      floating.parentId = ROOT_ID
    end
    if floating.clipTo ~= "attachedParent" then clipId = false end
    element.clipId = clipId or nil
    element.floating = floating
    ctx.openClipStack[#ctx.openClipStack + 1] = clipId
    ctx.treeRoots[#ctx.treeRoots + 1] = {
      element = element, parentId = floating.parentId,
      clipId = clipId or nil, zIndex = floating.zIndex,
    }
  end

  local clipConfig = config.clip
  if clipConfig and (clipConfig.horizontal or clipConfig.vertical) then
    local scrollData
    for i = 1, #ctx.scrollContainers do
      if ctx.scrollContainers[i].id == element.id then
        scrollData = ctx.scrollContainers[i]
        break
      end
    end
    if scrollData then
      scrollData.element = element
      scrollData.openThisFrame = true
    else
      scrollData = {
        id = element.id, element = element, openThisFrame = true,
        scrollX = 0, scrollY = 0,
        momentumX = 0, momentumY = 0, momentumTime = 0,
        pointerScrollActive = false,
        pointerOriginX = 0, pointerOriginY = 0,
        scrollOriginX = -1, scrollOriginY = -1,
        contentWidth = 0, contentHeight = 0,
        boundingBox = { x = 0, y = 0, width = 0, height = 0 },
      }
      ctx.scrollContainers[#ctx.scrollContainers + 1] = scrollData
    end
    -- The internal scroll offset is applied automatically unless the caller
    -- provides an explicit clip.childOffset.
    local offset = clipConfig.childOffset
    element.clip = {
      horizontal = clipConfig.horizontal or false,
      vertical = clipConfig.vertical or false,
      childOffsetX = offset and (offset.x or 0) or scrollData.scrollX,
      childOffsetY = offset and (offset.y or 0) or scrollData.scrollY,
    }
    ctx.openClipStack[#ctx.openClipStack + 1] = element.id
  end
end

local function openElement(config, parent)
  local id = config.id or (parent.id .. ":" .. (#parent.children + parent.floatingChildrenCount + 1))
  local element = {
    id = id,
    children = {},
    floatingChildrenCount = 0,
    width = 0, height = 0, minWidth = 0, minHeight = 0,
  }
  local clipTop = ctx.openClipStack[#ctx.openClipStack]
  if clipTop then element.clipId = clipTop end
  ctx.openStack[#ctx.openStack + 1] = element
  addElementData(id, element)
  applyDeclaration(element, config, parent)
  return element
end

-- Port of Clay__CloseElement: computes "fit" sizing bottom-up. Along the layout
-- axis children sum with gaps and padding, across it the max child wins, then
-- both axes clamp to the configured min/max.
local function closeElement()
  local element = ctx.openStack[#ctx.openStack]
  local layout = element.layout
  local clipH = element.clip ~= nil and element.clip.horizontal
  local clipV = element.clip ~= nil and element.clip.vertical
  if clipH or clipV or element.floating then
    ctx.openClipStack[#ctx.openClipStack] = nil
  end

  local padX = layout.padding.left + layout.padding.right
  local padY = layout.padding.top + layout.padding.bottom
  local children = element.children
  local childCount = #children
  local gapTotal = max(childCount - 1, 0) * layout.childGap

  if layout.leftToRight then
    element.width = padX
    element.minWidth = padX
    for i = 1, childCount do
      local child = children[i]
      element.width = element.width + child.width
      element.height = max(element.height, child.height + padY)
      if not clipH then element.minWidth = element.minWidth + child.minWidth end
      if not clipV then element.minHeight = max(element.minHeight, child.minHeight + padY) end
    end
    element.width = element.width + gapTotal
    if not clipH then element.minWidth = element.minWidth + gapTotal end
  else
    element.height = padY
    element.minHeight = padY
    for i = 1, childCount do
      local child = children[i]
      element.height = element.height + child.height
      element.width = max(element.width, child.width + padX)
      if not clipV then element.minHeight = element.minHeight + child.minHeight end
      if not clipH then element.minWidth = max(element.minWidth, child.minWidth + padX) end
    end
    element.height = element.height + gapTotal
    if not clipV then element.minHeight = element.minHeight + gapTotal end
  end

  local sw = layout.sizing.width
  if sw.type ~= "percent" then
    element.width = min(max(element.width, sw.min), sw.max)
    element.minWidth = min(max(element.minWidth, sw.min), sw.max)
  else
    element.width = 0
  end
  local sh = layout.sizing.height
  if sh.type ~= "percent" then
    element.height = min(max(element.height, sh.min), sh.max)
    element.minHeight = min(max(element.minHeight, sh.min), sh.max)
  else
    element.height = 0
  end

  updateAspectRatioBox(element)

  ctx.openStack[#ctx.openStack] = nil
  if #ctx.openStack > 1 then
    local parent = ctx.openStack[#ctx.openStack]
    if element.floating then
      parent.floatingChildrenCount = parent.floatingChildrenCount + 1
    else
      parent.children[#parent.children + 1] = element
    end
  end
end

-- config: the element declaration. children: optional function declaring child
-- elements, also accepted as config[1].
function Clay.element(config, children)
  assert(ctx, "clay: call Clay.initialize() before declaring elements")
  config = config or EMPTY
  if children == nil then children = config[1] end
  local parent = ctx.openStack[#ctx.openStack]
  assert(parent, "clay: Clay.element() must be called between beginLayout() and endLayout()")
  openElement(config, parent)
  if children then children() end
  closeElement()
end

function Clay.text(text, config)
  assert(ctx, "clay: call Clay.initialize() before declaring elements")
  local parent = ctx.openStack[#ctx.openStack]
  assert(parent, "clay: Clay.text() must be called between beginLayout() and endLayout()")
  text = tostring(text)
  local textConfig = normalizeTextConfig(config)
  local id = parent.id .. ":" .. (#parent.children + parent.floatingChildrenCount + 1)
  local measured = measureWords(text, textConfig)
  local lineHeight = textConfig.lineHeight > 0 and textConfig.lineHeight or measured.unwrappedHeight
  local element = {
    id = id,
    isText = true,
    text = text,
    textConfig = textConfig,
    measured = measured,
    preferredWidth = measured.unwrappedWidth,
    preferredHeight = measured.unwrappedHeight,
    children = {},
    floatingChildrenCount = 0,
    width = measured.unwrappedWidth,
    height = lineHeight,
    minWidth = measured.minWidth,
    minHeight = lineHeight,
  }
  local clipTop = ctx.openClipStack[#ctx.openClipStack]
  if clipTop then element.clipId = clipTop end
  addElementData(id, element)
  parent.children[#parent.children + 1] = element
end

function Clay.beginLayout()
  assert(ctx, "clay: call Clay.initialize() before beginLayout()")
  ctx.generation = ctx.generation + 1
  ctx.openStack = {}
  ctx.openClipStack = {}
  ctx.treeRoots = {}
  ctx.renderCommands = {}

  if measureCacheCount > ctx.maxMeasureCacheEntries then
    for key, item in pairs(measureCache) do
      if ctx.generation - item.generation > 2 then
        measureCache[key] = nil
        measureCacheCount = measureCacheCount - 1
      end
    end
  end
  if ctx.generation % 120 == 0 then
    for id, item in pairs(ctx.elementData) do
      if ctx.generation - item.generation > 120 then
        ctx.elementData[id] = nil
      end
    end
  end

  local root = {
    id = ROOT_ID, children = {}, floatingChildrenCount = 0,
    width = 0, height = 0, minWidth = 0, minHeight = 0,
  }
  ctx.openStack[1] = root
  addElementData(ROOT_ID, root)
  applyDeclaration(root, {
    layout = { sizing = { width = ctx.layoutWidth, height = ctx.layoutHeight } },
  }, root)
  -- The root sits on the stack twice, mirroring clay: parent lookups for
  -- top-level elements resolve to the root, and endLayout's close pops one.
  ctx.openStack[2] = root
  ctx.treeRoots[1] = { element = root, zIndex = 0 }
end

-- ## Sizing pass -----------------------------------------------------------------

local TEXT_SIZING = { type = "fit", min = 0, max = HUGE }

local function getSizing(element, xAxis)
  if element.isText then return TEXT_SIZING end
  if xAxis then return element.layout.sizing.width end
  return element.layout.sizing.height
end

local function getDim(element, xAxis)
  if xAxis then return element.width end
  return element.height
end

local function setDim(element, xAxis, value)
  if xAxis then element.width = value else element.height = value end
end

-- Port of Clay__SizeContainersAlongAxis. Per parent, top-down: percent children
-- get (parentSize - padding - gaps) * percent, grow children share leftover
-- space smallest-first up to their max, and overflowing content compresses
-- resizable children largest-first down to their min. Off the layout axis,
-- grow children expand to the parent's inner size and everything resizable is
-- clamped into it (except inside clip containers, which may overflow).
local function sizeContainersAlongAxis(xAxis, textElementsOut, aspectElementsOut)
  for rootIndex = 1, #ctx.treeRoots do
    local root = ctx.treeRoots[rootIndex]
    local rootElement = root.element

    if rootElement.floating then
      local parentItem = ctx.elementData[rootElement.floating.parentId]
      if parentItem and parentItem.element then
        local parentElement = parentItem.element
        local sizing = getSizing(rootElement, xAxis)
        if sizing.type == "grow" then
          setDim(rootElement, xAxis, getDim(parentElement, xAxis))
        elseif sizing.type == "percent" then
          setDim(rootElement, xAxis, getDim(parentElement, xAxis) * sizing.percent)
        end
      end
    end
    local rootSizing = getSizing(rootElement, xAxis)
    if rootSizing.type ~= "percent" then
      setDim(rootElement, xAxis, min(max(getDim(rootElement, xAxis), rootSizing.min), rootSizing.max))
    end

    local bfs = { rootElement }
    local bfsIndex = 1
    while bfsIndex <= #bfs do
      local parent = bfs[bfsIndex]
      bfsIndex = bfsIndex + 1
      local layout = parent.layout
      local growCount = 0
      local parentSize = getDim(parent, xAxis)
      local parentPadding
      if xAxis then
        parentPadding = layout.padding.left + layout.padding.right
      else
        parentPadding = layout.padding.top + layout.padding.bottom
      end
      local innerContentSize = 0
      local totalPaddingAndGaps = parentPadding
      local sizingAlongAxis = (xAxis and layout.leftToRight) or (not xAxis and not layout.leftToRight)
      local childGap = layout.childGap
      local isFirstChild = true
      local parentClipsAxis = false
      if parent.clip then
        if xAxis then parentClipsAxis = parent.clip.horizontal else parentClipsAxis = parent.clip.vertical end
      end
      local resizable = {}

      for i = 1, #parent.children do
        local child = parent.children[i]
        local childSizing = getSizing(child, xAxis)
        local childSize = getDim(child, xAxis)

        if textElementsOut and child.isText then
          textElementsOut[#textElementsOut + 1] = child
        elseif #child.children > 0 then
          bfs[#bfs + 1] = child
        end
        if aspectElementsOut and not child.isText and child.aspectRatio ~= 0 then
          aspectElementsOut[#aspectElementsOut + 1] = child
        end

        if childSizing.type ~= "percent" and childSizing.type ~= "fixed"
            and (not child.isText or child.textConfig.wrapMode == "words") then
          resizable[#resizable + 1] = child
        end

        if sizingAlongAxis then
          if childSizing.type ~= "percent" then
            innerContentSize = innerContentSize + childSize
          end
          if childSizing.type == "grow" then
            growCount = growCount + 1
          end
          if not isFirstChild then
            innerContentSize = innerContentSize + childGap
            totalPaddingAndGaps = totalPaddingAndGaps + childGap
          end
        else
          innerContentSize = max(childSize, innerContentSize)
        end
        isFirstChild = false
      end

      for i = 1, #parent.children do
        local child = parent.children[i]
        local childSizing = getSizing(child, xAxis)
        if childSizing.type == "percent" then
          local size = (parentSize - totalPaddingAndGaps) * childSizing.percent
          setDim(child, xAxis, size)
          if sizingAlongAxis then
            innerContentSize = innerContentSize + size
          end
          updateAspectRatioBox(child)
        end
      end

      if sizingAlongAxis then
        local sizeToDistribute = parentSize - parentPadding - innerContentSize
        if sizeToDistribute < 0 then
          -- Clip containers along this axis keep overflowing children at size;
          -- that overflow is what scrolling reveals.
          if not parentClipsAxis then
            while sizeToDistribute < -EPSILON and #resizable > 0 do
              local largest, secondLargest = 0, 0
              local sizeToAdd = sizeToDistribute
              for i = 1, #resizable do
                local size = getDim(resizable[i], xAxis)
                if not floatEqual(size, largest) then
                  if size > largest then
                    secondLargest = largest
                    largest = size
                  end
                  if size < largest then
                    secondLargest = max(secondLargest, size)
                    sizeToAdd = secondLargest - largest
                  end
                end
              end
              sizeToAdd = max(sizeToAdd, sizeToDistribute / #resizable)
              local i = 1
              while i <= #resizable do
                local child = resizable[i]
                local size = getDim(child, xAxis)
                local minSize
                if xAxis then minSize = child.minWidth else minSize = child.minHeight end
                local previous = size
                local removed = false
                if floatEqual(size, largest) then
                  size = size + sizeToAdd
                  if size <= minSize then
                    size = minSize
                    resizable[i] = resizable[#resizable]
                    resizable[#resizable] = nil
                    removed = true
                  end
                  setDim(child, xAxis, size)
                  sizeToDistribute = sizeToDistribute - (size - previous)
                end
                if not removed then i = i + 1 end
              end
            end
          end
        elseif sizeToDistribute > 0 and growCount > 0 then
          local growers = {}
          for i = 1, #resizable do
            if getSizing(resizable[i], xAxis).type == "grow" then
              growers[#growers + 1] = resizable[i]
            end
          end
          while sizeToDistribute > EPSILON and #growers > 0 do
            local smallest, secondSmallest = HUGE, HUGE
            local sizeToAdd = sizeToDistribute
            for i = 1, #growers do
              local size = getDim(growers[i], xAxis)
              if not floatEqual(size, smallest) then
                if size < smallest then
                  secondSmallest = smallest
                  smallest = size
                end
                if size > smallest then
                  secondSmallest = min(secondSmallest, size)
                  sizeToAdd = secondSmallest - smallest
                end
              end
            end
            sizeToAdd = min(sizeToAdd, sizeToDistribute / #growers)
            local i = 1
            while i <= #growers do
              local child = growers[i]
              local size = getDim(child, xAxis)
              local maxSize = getSizing(child, xAxis).max
              local previous = size
              local removed = false
              if floatEqual(size, smallest) then
                size = size + sizeToAdd
                if size >= maxSize then
                  size = maxSize
                  growers[i] = growers[#growers]
                  growers[#growers] = nil
                  removed = true
                end
                setDim(child, xAxis, size)
                sizeToDistribute = sizeToDistribute - (size - previous)
              end
              if not removed then i = i + 1 end
            end
          end
        end
      else
        for i = 1, #resizable do
          local child = resizable[i]
          local childSizing = getSizing(child, xAxis)
          local minSize
          if xAxis then minSize = child.minWidth else minSize = child.minHeight end
          local size = getDim(child, xAxis)
          local maxSize = parentSize - parentPadding
          if parentClipsAxis then
            maxSize = max(maxSize, innerContentSize)
          end
          if childSizing.type == "grow" then
            size = min(maxSize, childSizing.max)
          end
          setDim(child, xAxis, max(minSize, min(size, maxSize)))
        end
      end
    end
  end
end

-- ## Final layout and render command generation ----------------------------------

local function elementIsOffscreen(box)
  if not ctx.cullingEnabled then return false end
  return box.x > ctx.layoutWidth
      or box.y > ctx.layoutHeight
      or box.x + box.width < 0
      or box.y + box.height < 0
end

local function addCommand(command)
  ctx.renderCommands[#ctx.renderCommands + 1] = command
end

-- Port of the wrapping section of Clay__CalculateFinalLayout. Lines break when
-- the next measured word would overflow the element width or at newline
-- markers; a single word wider than the element gets its own line. Trailing
-- spaces are trimmed off wrapped lines.
local function wrapTextElement(element)
  local textConfig = element.textConfig
  local measured = element.measured
  local lines = {}
  element.wrappedLines = lines
  local lineHeight = textConfig.lineHeight > 0 and textConfig.lineHeight or element.preferredHeight

  if not measured.containsNewlines and element.preferredWidth <= element.width then
    lines[1] = { width = element.width, height = element.height, text = element.text }
    return
  end

  local spaceWidth = measureText(" ", textConfig)
  local text = element.text
  local words = measured.words
  local lineWidth = 0
  local lineLength = 0
  local lineStart = 1
  local wordIndex = 1
  while wordIndex <= #words do
    local word = words[wordIndex]
    if lineLength == 0 and lineWidth + word.width > element.width then
      local wordStr = text:sub(word.start, word.start + word.length - 1)
      local subStart = 1
      local wordLen = #wordStr
      while subStart <= wordLen do
        local subEnd = subStart
        local subW = 0
        while subEnd <= wordLen do
          local nextW = measureText(wordStr:sub(subStart, subEnd), textConfig)
          if nextW > element.width and subEnd > subStart then
            subEnd = subEnd - 1
            break
          end
          subW = nextW
          if nextW > element.width then break end
          if subEnd == wordLen then break end
          subEnd = subEnd + 1
        end
        lines[#lines + 1] = {
          width = subW, height = lineHeight,
          text = wordStr:sub(subStart, subEnd),
        }
        subStart = subEnd + 1
      end
      wordIndex = wordIndex + 1
      lineStart = word.start + word.length
    elseif word.length == 0 or lineWidth + word.width > element.width then
      local finalCharIsSpace = text:byte(max(lineStart + lineLength - 1, 1)) == 32
      local width = lineWidth + (finalCharIsSpace and -spaceWidth or 0)
      local length = lineLength + (finalCharIsSpace and -1 or 0)
      lines[#lines + 1] = {
        width = width, height = lineHeight,
        text = text:sub(lineStart, lineStart + length - 1),
      }
      if lineLength == 0 or word.length == 0 then
        wordIndex = wordIndex + 1
      end
      lineWidth = 0
      lineLength = 0
      lineStart = word.start
    else
      lineWidth = lineWidth + word.width
      lineLength = lineLength + word.length
      wordIndex = wordIndex + 1
    end
  end
  if lineLength > 0 then
    lines[#lines + 1] = {
      width = lineWidth, height = lineHeight,
      text = text:sub(lineStart, lineStart + lineLength - 1),
    }
  end
  element.height = lineHeight * #lines
end

-- Port of Clay__CalculateFinalLayout: X sizing, text wrap, aspect heights,
-- height propagation, Y sizing, aspect widths, z sort, then a DFS per root
-- that positions children and emits render commands. Borders and scissor ends
-- are emitted on the way back up so they draw over children.
local function calculateFinalLayout()
  local textElements = {}
  local aspectElements = {}
  sizeContainersAlongAxis(true, textElements, aspectElements)

  for i = 1, #textElements do
    wrapTextElement(textElements[i])
  end

  for i = 1, #aspectElements do
    local element = aspectElements[i]
    element.height = (1 / element.aspectRatio) * element.width
    element.layout.sizing.height.max = element.height
  end

  -- Propagate the effect of text wrapping and aspect scaling on parent heights.
  local dfs = {}
  for i = 1, #ctx.treeRoots do
    dfs[#dfs + 1] = { element = ctx.treeRoots[i].element, visited = false }
  end
  while #dfs > 0 do
    local node = dfs[#dfs]
    local element = node.element
    if not node.visited then
      node.visited = true
      if element.isText or #element.children == 0 then
        dfs[#dfs] = nil
      else
        for i = 1, #element.children do
          dfs[#dfs + 1] = { element = element.children[i], visited = false }
        end
      end
    else
      dfs[#dfs] = nil
      local layout = element.layout
      if layout.leftToRight then
        for i = 1, #element.children do
          local child = element.children[i]
          local childHeightWithPadding = max(child.height + layout.padding.top + layout.padding.bottom, element.height)
          element.height = min(max(childHeightWithPadding, layout.sizing.height.min), layout.sizing.height.max)
        end
      else
        local contentHeight = layout.padding.top + layout.padding.bottom
        for i = 1, #element.children do
          contentHeight = contentHeight + element.children[i].height
        end
        contentHeight = contentHeight + max(#element.children - 1, 0) * layout.childGap
        element.height = min(max(contentHeight, layout.sizing.height.min), layout.sizing.height.max)
      end
    end
  end

  sizeContainersAlongAxis(false, nil, nil)

  for i = 1, #aspectElements do
    local element = aspectElements[i]
    element.width = element.aspectRatio * element.height
  end

  -- Stable sort roots ascending by z index (table.sort alone is not stable).
  for i = 1, #ctx.treeRoots do
    ctx.treeRoots[i].order = i
  end
  table.sort(ctx.treeRoots, function(a, b)
    if a.zIndex ~= b.zIndex then return a.zIndex < b.zIndex end
    return a.order < b.order
  end)

  for rootIndex = 1, #ctx.treeRoots do
    local root = ctx.treeRoots[rootIndex]
    local rootElement = root.element
    local rootX, rootY = 0, 0

    if rootElement.floating then
      local parentItem = ctx.elementData[rootElement.floating.parentId]
      if parentItem then
        local floating = rootElement.floating
        local parentBox = parentItem.boundingBox
        local parentPoint = ATTACH_POINTS[floating.attachPoints.parent]
        local elementPoint = ATTACH_POINTS[floating.attachPoints.element]
        rootX = parentBox.x + parentBox.width * parentPoint[1]
          - rootElement.width * elementPoint[1] + floating.offset.x
        rootY = parentBox.y + parentBox.height * parentPoint[2]
          - rootElement.height * elementPoint[2] + floating.offset.y
      end
    end

    local rootClipItem = nil
    if root.clipId then rootClipItem = ctx.elementData[root.clipId] end
    local rootClipActive = rootClipItem ~= nil and not elementIsOffscreen(rootClipItem.boundingBox)
    if rootClipActive then
      addCommand({
        type = "scissorStart",
        boundingBox = rootClipItem.boundingBox,
        id = rootElement.id .. ":rootClip",
        zIndex = root.zIndex or 0,
      })
    end

    local dfsStack = { {
      element = rootElement, x = rootX, y = rootY,
      nextX = rootElement.layout.padding.left,
      nextY = rootElement.layout.padding.top,
      visited = false,
    } }

    while #dfsStack > 0 do
      local node = dfsStack[#dfsStack]
      local element = node.element
      local layout
      if element.isText then layout = DEFAULT_LAYOUT else layout = element.layout end
      local scrollOffsetX, scrollOffsetY = 0, 0

      if node.visited then
        -- Returning upwards: borders, overlay end, and scissor end draw after
        -- (over) the element's children.
        dfsStack[#dfsStack] = nil
        if not element.isText then
          local data = ctx.elementData[element.id]
          if not elementIsOffscreen(data.boundingBox) then
            local closeClip = false
            if element.clip then
              closeClip = true
              scrollOffsetX = element.clip.childOffsetX
              scrollOffsetY = element.clip.childOffsetY
            end
            local border = element.border
            if border then
              local box = data.boundingBox
              addCommand({
                type = "border", boundingBox = box,
                color = border.color, cornerRadius = element.cornerRadius,
                width = border.width, userData = element.userData,
                id = element.id, zIndex = root.zIndex or 0,
              })
              if border.width.betweenChildren > 0 and border.color[4] > 0 then
                local halfGap = layout.childGap / 2
                local halfWidth = border.width.betweenChildren / 2
                if layout.leftToRight then
                  local offset = layout.padding.left - halfGap
                  for i = 1, #element.children do
                    local child = element.children[i]
                    if i > 1 then
                      addCommand({
                        type = "rectangle",
                        boundingBox = {
                          x = box.x + offset + scrollOffsetX - halfWidth,
                          y = box.y + scrollOffsetY,
                          width = border.width.betweenChildren,
                          height = element.height,
                        },
                        color = border.color,
                        userData = element.userData,
                        id = element.id .. ":separator" .. i,
                        zIndex = root.zIndex or 0,
                      })
                    end
                    offset = offset + child.width + layout.childGap
                  end
                else
                  local offset = layout.padding.top - halfGap
                  for i = 1, #element.children do
                    local child = element.children[i]
                    if i > 1 then
                      addCommand({
                        type = "rectangle",
                        boundingBox = {
                          x = box.x + scrollOffsetX,
                          y = box.y + offset + scrollOffsetY - halfWidth,
                          width = element.width,
                          height = border.width.betweenChildren,
                        },
                        color = border.color,
                        userData = element.userData,
                        id = element.id .. ":separator" .. i,
                        zIndex = root.zIndex or 0,
                      })
                    end
                    offset = offset + child.height + layout.childGap
                  end
                end
              end
            end
            if element.overlayColor and element.overlayColor[4] > 0 then
              addCommand({ type = "overlayEnd", id = element.id, zIndex = root.zIndex or 0 })
            end
            if closeClip then
              addCommand({ type = "scissorEnd", id = element.id, zIndex = root.zIndex or 0 })
            end
          end
        end
      else
        node.visited = true
        local x, y = node.x, node.y
        local width, height = element.width, element.height
        local scrollData = nil

        if not element.isText then
          if element.floating then
            local expand = element.floating.expand
            x = x - expand.width
            width = width + expand.width * 2
            y = y - expand.height
            height = height + expand.height * 2
          end
          if element.clip then
            for i = 1, #ctx.scrollContainers do
              if ctx.scrollContainers[i].id == element.id then
                scrollData = ctx.scrollContainers[i]
                break
              end
            end
            if scrollData then
              local scrollBox = scrollData.boundingBox
              scrollBox.x, scrollBox.y, scrollBox.width, scrollBox.height = x, y, width, height
              local maxSX = max((scrollData.contentWidth or 0) - width, 0)
              local maxSY = max((scrollData.contentHeight or 0) - height, 0)
              scrollData.scrollX = min(max(scrollData.scrollX, -maxSX), 0)
              scrollData.scrollY = min(max(scrollData.scrollY, -maxSY), 0)
              element.clip.childOffsetX = scrollData.scrollX
              element.clip.childOffsetY = scrollData.scrollY
            end
            scrollOffsetX = element.clip.childOffsetX
            scrollOffsetY = element.clip.childOffsetY
          end
        end

        local box = { x = x, y = y, width = width, height = height }
        local offscreen = elementIsOffscreen(box)

        if not offscreen then
          if element.isText then
            local textConfig = element.textConfig
            local natural = element.preferredHeight
            local finalLineHeight = textConfig.lineHeight > 0 and textConfig.lineHeight or natural
            local yPosition = (finalLineHeight - natural) / 2
            for lineIndex = 1, #element.wrappedLines do
              local line = element.wrappedLines[lineIndex]
              if #line.text > 0 then
                local offset = box.width - line.width
                if textConfig.alignment == "left" then
                  offset = 0
                elseif textConfig.alignment == "center" then
                  offset = offset / 2
                end
                addCommand({
                  type = "text",
                  boundingBox = { x = box.x + offset, y = box.y + yPosition, width = line.width, height = line.height },
                  text = line.text,
                  color = textConfig.color,
                  fontId = textConfig.fontId,
                  fontSize = textConfig.fontSize,
                  lineHeight = textConfig.lineHeight,
                  userData = textConfig.userData,
                  id = element.id .. ":" .. lineIndex,
                  zIndex = root.zIndex or 0,
                })
              end
              yPosition = yPosition + finalLineHeight
              if ctx.cullingEnabled and box.y + yPosition > ctx.layoutHeight then
                break
              end
            end
          else
            if element.overlayColor and element.overlayColor[4] > 0 then
              addCommand({
                type = "overlayStart", color = element.overlayColor,
                userData = element.userData, id = element.id, zIndex = root.zIndex or 0,
              })
            end
            if element.image ~= nil then
              addCommand({
                type = "image", boundingBox = box, image = element.image,
                color = element.backgroundColor, cornerRadius = element.cornerRadius,
                userData = element.userData, id = element.id, zIndex = root.zIndex or 0,
              })
            end
            if element.custom ~= nil then
              addCommand({
                type = "custom", boundingBox = box, customData = element.custom,
                color = element.backgroundColor, cornerRadius = element.cornerRadius,
                userData = element.userData, id = element.id, zIndex = root.zIndex or 0,
              })
            end
            if element.clip then
              addCommand({
                type = "scissorStart", boundingBox = box,
                horizontal = element.clip.horizontal, vertical = element.clip.vertical,
                userData = element.userData, id = element.id, zIndex = root.zIndex or 0,
              })
            end
            if element.backgroundColor and element.backgroundColor[4] > 0 then
              addCommand({
                type = "rectangle", boundingBox = box,
                color = element.backgroundColor, cornerRadius = element.cornerRadius,
                userData = element.userData, id = element.id, zIndex = root.zIndex or 0,
              })
            end
          end
        end

        local data = ctx.elementData[element.id]
        if data then data.boundingBox = box end

        if not element.isText then
          -- On-axis alignment shifts the first child by the leftover space.
          local contentWidth, contentHeight = 0, 0
          if layout.leftToRight then
            for i = 1, #element.children do
              local child = element.children[i]
              contentWidth = contentWidth + child.width
              contentHeight = max(contentHeight, child.height)
            end
            contentWidth = contentWidth + max(#element.children - 1, 0) * layout.childGap
            local extraSpace = element.width - (layout.padding.left + layout.padding.right) - contentWidth
            if layout.alignX == "left" then
              extraSpace = 0
            elseif layout.alignX == "center" then
              extraSpace = extraSpace / 2
            end
            node.nextX = node.nextX + max(0, extraSpace)
          else
            for i = 1, #element.children do
              local child = element.children[i]
              contentWidth = max(contentWidth, child.width)
              contentHeight = contentHeight + child.height
            end
            contentHeight = contentHeight + max(#element.children - 1, 0) * layout.childGap
            local extraSpace = element.height - (layout.padding.top + layout.padding.bottom) - contentHeight
            if layout.alignY == "top" then
              extraSpace = 0
            elseif layout.alignY == "center" then
              extraSpace = extraSpace / 2
            end
            node.nextY = node.nextY + max(0, extraSpace)
          end

          if scrollData then
            scrollData.contentWidth = contentWidth + layout.padding.left + layout.padding.right
            scrollData.contentHeight = contentHeight + layout.padding.top + layout.padding.bottom
          end

          local childNodes = {}
          for i = 1, #element.children do
            local child = element.children[i]
            if layout.leftToRight then
              node.nextY = layout.padding.top
              local whitespace = element.height - (layout.padding.top + layout.padding.bottom) - child.height
              if layout.alignY == "center" then
                node.nextY = node.nextY + whitespace / 2
              elseif layout.alignY == "bottom" then
                node.nextY = node.nextY + whitespace
              end
            else
              node.nextX = layout.padding.left
              local whitespace = element.width - (layout.padding.left + layout.padding.right) - child.width
              if layout.alignX == "center" then
                node.nextX = node.nextX + whitespace / 2
              elseif layout.alignX == "right" then
                node.nextX = node.nextX + whitespace
              end
            end
            local childLayout
            if child.isText then childLayout = DEFAULT_LAYOUT else childLayout = child.layout end
            childNodes[i] = {
              element = child,
              x = box.x + node.nextX + scrollOffsetX,
              y = box.y + node.nextY + scrollOffsetY,
              nextX = childLayout.padding.left,
              nextY = childLayout.padding.top,
              visited = false,
            }
            if layout.leftToRight then
              node.nextX = node.nextX + child.width + layout.childGap
            else
              node.nextY = node.nextY + child.height + layout.childGap
            end
          end
          -- Pushed in reverse so the stack visits children in declaration order.
          for i = #childNodes, 1, -1 do
            dfsStack[#dfsStack + 1] = childNodes[i]
          end
        end
      end
    end

    if rootClipActive then
      addCommand({ type = "scissorEnd", id = rootElement.id .. ":rootClip", zIndex = root.zIndex or 0 })
    end
  end
end

function Clay.endLayout()
  assert(ctx, "clay: call Clay.initialize() before endLayout()")
  closeElement()
  if #ctx.openStack > 1 then
    ctx.errorHandler("clay: unbalanced element open/close detected at endLayout()")
  end
  calculateFinalLayout()
  return ctx.renderCommands
end

-- ## Pointer input ----------------------------------------------------------------

local function pointInBox(x, y, box)
  return x >= box.x and x <= box.x + box.width and y >= box.y and y <= box.y + box.height
end

-- Pointer state is one of "pressedThisFrame", "pressed", "releasedThisFrame",
-- "released".
function Clay.getPointerState()
  return { x = ctx.pointer.x, y = ctx.pointer.y, state = ctx.pointer.state }
end

-- Port of Clay_SetPointerState. Hit tests against the previous frame's
-- bounding boxes, so call it once per frame before beginLayout. Elements
-- inside clip containers only count as hovered while the pointer is inside
-- the clip box; floating roots with pointerCaptureMode "capture" block
-- everything underneath.
function Clay.setPointerState(x, y, isPointerDown)
  assert(ctx, "clay: call Clay.initialize() before setPointerState()")
  ctx.pointer.x, ctx.pointer.y = x, y
  local overIds, overSet = {}, {}
  ctx.pointerOverIds, ctx.pointerOverSet = overIds, overSet

  for rootIndex = #ctx.treeRoots, 1, -1 do
    local root = ctx.treeRoots[rootIndex]
    local found = false
    local stack = { root.element }
    while #stack > 0 do
      local element = stack[#stack]
      stack[#stack] = nil
      local data = ctx.elementData[element.id]
      if data and data.generation > ctx.generation then
        local insideClip = true
        if element.clipId then
          local clipData = ctx.elementData[element.clipId]
          insideClip = clipData ~= nil and pointInBox(x, y, clipData.boundingBox)
        end
        if insideClip and pointInBox(x, y, data.boundingBox) then
          if data.onHover then
            data.onHover(element.id, Clay.getPointerState(), data.onHoverUserData)
          end
          overIds[#overIds + 1] = element.id
          overSet[element.id] = true
          found = true
        end
        for i = #element.children, 1, -1 do
          stack[#stack + 1] = element.children[i]
        end
      end
    end
    local rootElement = root.element
    if found and rootElement.floating and rootElement.floating.pointerCaptureMode ~= "passthrough" then
      break
    end
  end

  local state = ctx.pointer.state
  if isPointerDown then
    if state == "pressedThisFrame" then
      ctx.pointer.state = "pressed"
    elseif state ~= "pressed" then
      ctx.pointer.state = "pressedThisFrame"
    end
  else
    if state == "releasedThisFrame" then
      ctx.pointer.state = "released"
    elseif state ~= "released" then
      ctx.pointer.state = "releasedThisFrame"
    end
  end
end

function Clay.pointerOver(id)
  return ctx ~= nil and ctx.pointerOverSet[id] == true
end

-- True when the pointer is over the element currently being declared. Valid
-- inside a Clay.element children function.
function Clay.hovered()
  if not ctx then return false end
  local open = ctx.openStack[#ctx.openStack]
  return open ~= nil and ctx.pointerOverSet[open.id] == true
end

-- Registers fn(elementId, pointerState, userData) on the element currently
-- being declared. It fires from setPointerState while the pointer is over the
-- element, and resets each frame like clay's Clay_OnHover.
function Clay.onHover(fn, userData)
  local open = ctx.openStack[#ctx.openStack]
  local data = open and ctx.elementData[open.id]
  if data then
    data.onHover = fn
    data.onHoverUserData = userData
  end
end

-- ## Scroll containers --------------------------------------------------------------

-- Port of Clay_UpdateScrollContainers: applies wheel deltas and optional drag
-- scrolling with momentum to the innermost hovered scroll container, clamping
-- to content bounds. Call once per frame before beginLayout, passing wheel
-- deltas straight from love.wheelmoved.
function Clay.updateScrollContainers(enableDragScrolling, scrollDeltaX, scrollDeltaY, deltaTime)
  assert(ctx, "clay: call Clay.initialize() before updateScrollContainers()")
  scrollDeltaX = scrollDeltaX or 0
  scrollDeltaY = scrollDeltaY or 0
  deltaTime = deltaTime or 0
  local pointerState = ctx.pointer.state
  local isPointerActive = enableDragScrolling
    and (pointerState == "pressed" or pointerState == "pressedThisFrame")
  local highestPriorityScrollData = nil
  local containers = ctx.scrollContainers

  local i = 1
  while i <= #containers do
    local scrollData = containers[i]
    local removed = false
    if not scrollData.openThisFrame then
      containers[i] = containers[#containers]
      containers[#containers] = nil
      removed = true
    else
      scrollData.openThisFrame = false
      if not ctx.elementData[scrollData.id] then
        containers[i] = containers[#containers]
        containers[#containers] = nil
        removed = true
      else
        -- Pointer released after a drag: convert the drag distance into
        -- momentum that decays 5% per update.
        if not isPointerActive and scrollData.pointerScrollActive then
          local xDiff = scrollData.scrollX - scrollData.scrollOriginX
          if xDiff < -10 or xDiff > 10 then
            scrollData.momentumX = scrollData.momentumTime > 0 and xDiff / (scrollData.momentumTime * 25) or 0
          end
          local yDiff = scrollData.scrollY - scrollData.scrollOriginY
          if yDiff < -10 or yDiff > 10 then
            scrollData.momentumY = scrollData.momentumTime > 0 and yDiff / (scrollData.momentumTime * 25) or 0
          end
          scrollData.pointerScrollActive = false
          scrollData.pointerOriginX, scrollData.pointerOriginY = 0, 0
          scrollData.scrollOriginX, scrollData.scrollOriginY = 0, 0
          scrollData.momentumTime = 0
        end

        local scrollOccurred = scrollDeltaX ~= 0 or scrollDeltaY ~= 0
        scrollData.scrollX = scrollData.scrollX + scrollData.momentumX
        scrollData.momentumX = scrollData.momentumX * 0.95
        if (scrollData.momentumX > -0.1 and scrollData.momentumX < 0.1) or scrollOccurred then
          scrollData.momentumX = 0
        end
        scrollData.scrollX = min(max(scrollData.scrollX,
          -max(scrollData.contentWidth - scrollData.element.width, 0)), 0)

        scrollData.scrollY = scrollData.scrollY + scrollData.momentumY
        scrollData.momentumY = scrollData.momentumY * 0.95
        if (scrollData.momentumY > -0.1 and scrollData.momentumY < 0.1) or scrollOccurred then
          scrollData.momentumY = 0
        end
        scrollData.scrollY = min(max(scrollData.scrollY,
          -max(scrollData.contentHeight - scrollData.element.height, 0)), 0)

        for j = 1, #ctx.pointerOverIds do
          if scrollData.id == ctx.pointerOverIds[j] then
            highestPriorityScrollData = scrollData
          end
        end
      end
    end
    if not removed then i = i + 1 end
  end

  if highestPriorityScrollData then
    local scrollData = highestPriorityScrollData
    local element = scrollData.element
    local clip = element.clip
    local canScrollVertically = clip.vertical and scrollData.contentHeight > element.height
    local canScrollHorizontally = clip.horizontal and scrollData.contentWidth > element.width
    if canScrollVertically then
      local dy = scrollDeltaY
      if dy > 5 or dy < -5 then dy = dy / 100 end
      scrollData.scrollY = scrollData.scrollY + dy * 30
    end
    if canScrollHorizontally then
      local dx = scrollDeltaX
      if dx > 5 or dx < -5 then dx = dx / 100 end
      scrollData.scrollX = scrollData.scrollX + dx * 30
    end
    if isPointerActive then
      scrollData.momentumX, scrollData.momentumY = 0, 0
      if not scrollData.pointerScrollActive then
        scrollData.pointerOriginX, scrollData.pointerOriginY = ctx.pointer.x, ctx.pointer.y
        scrollData.scrollOriginX, scrollData.scrollOriginY = scrollData.scrollX, scrollData.scrollY
        scrollData.pointerScrollActive = true
      else
        local deltaX, deltaY = 0, 0
        if canScrollHorizontally then
          local old = scrollData.scrollX
          scrollData.scrollX = scrollData.scrollOriginX + (ctx.pointer.x - scrollData.pointerOriginX)
          scrollData.scrollX = max(min(scrollData.scrollX, 0),
            -(scrollData.contentWidth - scrollData.boundingBox.width))
          deltaX = scrollData.scrollX - old
        end
        if canScrollVertically then
          local old = scrollData.scrollY
          scrollData.scrollY = scrollData.scrollOriginY + (ctx.pointer.y - scrollData.pointerOriginY)
          scrollData.scrollY = max(min(scrollData.scrollY, 0),
            -(scrollData.contentHeight - scrollData.boundingBox.height))
          deltaY = scrollData.scrollY - old
        end
        -- Holding still resets the drag origin so momentum reflects only the
        -- final flick.
        if deltaX > -0.1 and deltaX < 0.1 and deltaY > -0.1 and deltaY < 0.1
            and scrollData.momentumTime > 0.15 then
          scrollData.momentumTime = 0
          scrollData.pointerOriginX, scrollData.pointerOriginY = ctx.pointer.x, ctx.pointer.y
          scrollData.scrollOriginX, scrollData.scrollOriginY = scrollData.scrollX, scrollData.scrollY
        else
          scrollData.momentumTime = scrollData.momentumTime + deltaTime
        end
      end
    end
    if canScrollVertically then
      scrollData.scrollY = max(min(scrollData.scrollY, 0), -(scrollData.contentHeight - element.height))
    end
    if canScrollHorizontally then
      scrollData.scrollX = max(min(scrollData.scrollX, 0), -(scrollData.contentWidth - element.width))
    end
  end
end

-- Current scroll offset for an element id; with no id, the element currently
-- being declared.
function Clay.getScrollOffset(id)
  if not ctx then return { x = 0, y = 0 } end
  if id == nil then
    local open = ctx.openStack[#ctx.openStack]
    id = open and open.id
  end
  for i = 1, #ctx.scrollContainers do
    local scrollData = ctx.scrollContainers[i]
    if scrollData.id == id then
      return { x = scrollData.scrollX, y = scrollData.scrollY }
    end
  end
  return { x = 0, y = 0 }
end

-- Returns the internal scroll state table for an element id, or nil. Mutable
-- fields: scrollX, scrollY. Informational fields: contentWidth, contentHeight,
-- boundingBox, element.
function Clay.getScrollContainerData(id)
  if not ctx then return nil end
  for i = 1, #ctx.scrollContainers do
    if ctx.scrollContainers[i].id == id then
      return ctx.scrollContainers[i]
    end
  end
  return nil
end

function Clay.scrollToTop(id)
  local sd = Clay.getScrollContainerData(id)
  if sd then
    sd.scrollY = 0
    sd.momentumY = 0
  end
end

function Clay.scrollToBottom(id)
  local sd = Clay.getScrollContainerData(id)
  if sd then
    local elemH = (sd.element and sd.element.height) or sd.boundingBox.height or 0
    local maxSY = max((sd.contentHeight or 0) - elemH, 0)
    sd.scrollY = -maxSY
    sd.momentumY = 0
  end
end

function Clay.scrollToEnd(id)
  local sd = Clay.getScrollContainerData(id)
  if sd then
    local elemW = (sd.element and sd.element.width) or sd.boundingBox.width or 0
    local maxSX = max((sd.contentWidth or 0) - elemW, 0)
    sd.scrollX = -maxSX
    sd.momentumX = 0
  end
end

-- Last computed bounding box for an element id, from the most recent layout.
function Clay.getElementData(id)
  local data = ctx and ctx.elementData[id]
  if not data then
    return { found = false, x = 0, y = 0, width = 0, height = 0 }
  end
  local box = data.boundingBox
  return { found = true, x = box.x, y = box.y, width = box.width, height = box.height }
end

-- Current scroll state for a clip element: scrollY, contentHeight, elementHeight.
function Clay.getScrollState(id)
  if not ctx then return nil end
  for i = 1, #ctx.scrollContainers do
    local s = ctx.scrollContainers[i]
    if s.id == id then
      return {
        scrollY = s.scrollY,
        contentHeight = s.contentHeight,
        elementHeight = s.element and s.element.height or 0,
      }
    end
  end
  return nil
end

-- ## LOVE renderer ------------------------------------------------------------------

local customRenderHandler = nil

-- fn(command) receives "custom" render commands carrying .boundingBox and
-- .customData from elements declared with a custom field.
function Clay.setCustomRenderHandler(fn)
  customRenderHandler = fn
end

local function setDrawColor(color, overlayStack)
  local r, g, b, a = color[1], color[2], color[3], color[4] or 1
  local overlay = overlayStack[#overlayStack]
  if overlay then
    local t = overlay[4] or 1
    r = r + (overlay[1] - r) * t
    g = g + (overlay[2] - g) * t
    b = b + (overlay[3] - b) * t
  end
  love.graphics.setColor(r, g, b, a)
end

local function clampedCorners(corners, width, height)
  if not corners then return 0, 0, 0, 0 end
  local half = min(width, height) / 2
  return min(corners.topLeft, half), min(corners.topRight, half),
    min(corners.bottomLeft, half), min(corners.bottomRight, half)
end

local function roundedRectPoints(x, y, width, height, tl, tr, bl, br)
  local points = {}
  local function corner(cx, cy, radius, a0, a1)
    if radius <= 0 then
      points[#points + 1] = cx
      points[#points + 1] = cy
      return
    end
    local segments = max(3, floor(radius / 3) + 3)
    for s = 0, segments do
      local angle = a0 + (a1 - a0) * s / segments
      points[#points + 1] = cx + math.cos(angle) * radius
      points[#points + 1] = cy + math.sin(angle) * radius
    end
  end
  local pi = math.pi
  corner(x + tl, y + tl, tl, pi, pi * 1.5)
  corner(x + width - tr, y + tr, tr, pi * 1.5, pi * 2)
  corner(x + width - br, y + height - br, br, 0, pi * 0.5)
  corner(x + bl, y + height - bl, bl, pi * 0.5, pi)
  return points
end

local function drawRoundedRectangle(box, corners)
  local tl, tr, bl, br = clampedCorners(corners, box.width, box.height)
  if tl == 0 and tr == 0 and bl == 0 and br == 0 then
    love.graphics.rectangle("fill", box.x, box.y, box.width, box.height)
  elseif tl == tr and tl == bl and tl == br then
    love.graphics.rectangle("fill", box.x, box.y, box.width, box.height, tl, tl)
  else
    love.graphics.polygon("fill", roundedRectPoints(box.x, box.y, box.width, box.height, tl, tr, bl, br))
  end
end

local function drawCornerArc(cx, cy, radius, a0, a1, thickness)
  if radius <= 0 or thickness <= 0 then return end
  love.graphics.setLineWidth(thickness)
  love.graphics.arc("line", "open", cx, cy, radius - thickness / 2, a0, a1)
end

-- Borders draw as four inset side rectangles plus stroked arcs at rounded
-- corners, the same construction clay's official renderers use.
local function drawBorder(command, overlayStack)
  local box = command.boundingBox
  local width = command.width
  setDrawColor(command.color, overlayStack)
  local tl, tr, bl, br = clampedCorners(command.cornerRadius, box.width, box.height)
  local g = love.graphics
  if width.left > 0 then
    g.rectangle("fill", box.x, box.y + tl, width.left, box.height - tl - bl)
  end
  if width.right > 0 then
    g.rectangle("fill", box.x + box.width - width.right, box.y + tr, width.right, box.height - tr - br)
  end
  if width.top > 0 then
    g.rectangle("fill", box.x + tl, box.y, box.width - tl - tr, width.top)
  end
  if width.bottom > 0 then
    g.rectangle("fill", box.x + bl, box.y + box.height - width.bottom, box.width - bl - br, width.bottom)
  end
  local pi = math.pi
  drawCornerArc(box.x + tl, box.y + tl, tl, pi, pi * 1.5, max(width.top, width.left))
  drawCornerArc(box.x + box.width - tr, box.y + tr, tr, pi * 1.5, pi * 2, max(width.top, width.right))
  drawCornerArc(box.x + box.width - br, box.y + box.height - br, br, 0, pi * 0.5, max(width.bottom, width.right))
  drawCornerArc(box.x + bl, box.y + box.height - bl, bl, pi * 0.5, pi, max(width.bottom, width.left))
end

local function drawImage(command, overlayStack)
  local image = command.image
  local box = command.boundingBox
  if command.color and command.color[4] > 0 then
    setDrawColor(command.color, overlayStack)
  else
    setDrawColor(WHITE, overlayStack)
  end
  local imageWidth, imageHeight = 1, 1
  if image.getDimensions then
    imageWidth, imageHeight = image:getDimensions()
  end
  local corners = command.cornerRadius
  local rounded = corners ~= nil and (corners.topLeft > 0 or corners.topRight > 0
    or corners.bottomLeft > 0 or corners.bottomRight > 0)
  -- Rounded images mask through the stencil buffer, available on the default
  -- window unless disabled in conf.lua.
  local useStencil = rounded and love.graphics.stencil ~= nil
  if useStencil then
    love.graphics.stencil(function()
      drawRoundedRectangle(box, corners)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
  end
  love.graphics.draw(image, box.x, box.y, 0, box.width / imageWidth, box.height / imageHeight)
  if useStencil then
    love.graphics.setStencilTest()
  end
end

-- Draws a command list from endLayout with love.graphics. Graphics state is
-- saved and restored around the whole pass, and nested clip regions intersect.
function Clay.render(commands)
  commands = commands or (ctx and ctx.renderCommands) or EMPTY
  local g = love.graphics
  g.push("all")
  local scissorStack = {}
  local overlayStack = {}
  for i = 1, #commands do
    local command = commands[i]
    local commandType = command.type
    if commandType == "rectangle" then
      setDrawColor(command.color, overlayStack)
      drawRoundedRectangle(command.boundingBox, command.cornerRadius)
    elseif commandType == "text" then
      g.setFont(getFont(command.fontId, command.fontSize))
      setDrawColor(command.color, overlayStack)
      -- Rounded to whole pixels; fractional positions blur glyphs under the
      -- default linear filter.
      g.print(command.text, floor(command.boundingBox.x + 0.5), floor(command.boundingBox.y + 0.5))
    elseif commandType == "border" then
      drawBorder(command, overlayStack)
    elseif commandType == "image" then
      drawImage(command, overlayStack)
    elseif commandType == "scissorStart" then
      scissorStack[#scissorStack + 1] = { g.getScissor() }
      local box = command.boundingBox
      local x, y, width, height = box.x, box.y, box.width, box.height
      if x < 0 then width = width + x; x = 0 end
      if y < 0 then height = height + y; y = 0 end
      g.intersectScissor(x, y, max(width, 0), max(height, 0))
    elseif commandType == "scissorEnd" then
      local previous = scissorStack[#scissorStack]
      scissorStack[#scissorStack] = nil
      if previous and previous[1] then
        g.setScissor(previous[1], previous[2], previous[3], previous[4])
      else
        g.setScissor()
      end
    elseif commandType == "overlayStart" then
      overlayStack[#overlayStack + 1] = command.color
    elseif commandType == "overlayEnd" then
      overlayStack[#overlayStack] = nil
    elseif commandType == "custom" then
      if customRenderHandler then customRenderHandler(command) end
    end
  end
  g.pop()
end

return Clay
