local api = require('love-api.love_api')

local state = "menu"
local font

local modules = {}
for i, m in ipairs(api.modules) do
    table.insert(modules, m)
end

local scroll = 0
local selected_module = nil

function love.load()
    font = love.graphics.newFont(14)
    love.graphics.setFont(font)
end

function love.draw()
    local width, height = love.graphics.getDimensions()

    if state == "menu" then
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("LÖVE API Viewer", 0, height / 2 - 60, width, "center")
        
        local mx, my = love.mouse.getPosition()
        local bw, bh = 200, 40
        local bx, by = width / 2 - bw / 2, height / 2
        
        local hover = mx > bx and mx < bx + bw and my > by and my < by + bh
        if hover then
            love.graphics.setColor(0.4, 0.4, 0.4)
        else
            love.graphics.setColor(0.2, 0.2, 0.2)
        end
        love.graphics.rectangle("fill", bx, by, bw, bh, 5)
        
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("View Documentation", bx, by + 12, bw, "center")
        
    elseif state == "api_list" then
        love.graphics.setColor(0.8, 0.8, 0.8)
        love.graphics.print("LÖVE API Modules (Click to view, ESC to go back)", 20, 20)
        
        local mx, my = love.mouse.getPosition()
        
        for i, m in ipairs(modules) do
            local y = 60 + (i - 1) * 35 + scroll
            local bx, by, bw, bh = 20, y, 300, 30
            
            if my > 60 and my < height - 20 then
                if mx > bx and mx < bx + bw and my > by and my < by + bh then
                    love.graphics.setColor(0.4, 0.4, 0.4)
                else
                    love.graphics.setColor(0.2, 0.2, 0.2)
                end
                love.graphics.rectangle("fill", bx, by, bw, bh, 4)
                
                love.graphics.setColor(1, 1, 1)
                love.graphics.print(m.name, bx + 10, by + 8)
            end
        end
        
    elseif state == "api_detail" then
        love.graphics.setColor(0.8, 0.8, 0.8)
        love.graphics.print("Module: " .. selected_module.name .. " (ESC to go back)", 20, 20)
        
        local y = 60 + scroll
        local wrap_limit = width - 40
        
        love.graphics.setColor(1, 1, 1)
        local _, wrapped_desc = font:getWrap(selected_module.description or "No description.", wrap_limit)
        for _, line in ipairs(wrapped_desc) do
            love.graphics.print(line, 20, y)
            y = y + 20
        end
        y = y + 20
        
        if selected_module.functions then
            love.graphics.setColor(0.5, 0.8, 0.5)
            love.graphics.print("Functions:", 20, y)
            y = y + 25
            
            for i, f in ipairs(selected_module.functions) do
                if y > 20 and y < height + 100 then -- Simple culling
                    love.graphics.setColor(0.4, 0.7, 1)
                    love.graphics.print(f.name, 20, y)
                    y = y + 20
                    
                    love.graphics.setColor(0.7, 0.7, 0.7)
                    local _, wrapped = font:getWrap(f.description or "", wrap_limit)
                    for _, line in ipairs(wrapped) do
                        love.graphics.print(line, 40, y)
                        y = y + 16
                    end
                    y = y + 10
                else
                    -- Still need to calculate height if culled so scroll height is correct
                    y = y + 20
                    local _, wrapped = font:getWrap(f.description or "", wrap_limit)
                    y = y + 16 * #wrapped + 10
                end
            end
        else
            love.graphics.print("No functions documented.", 20, y)
        end
    end
end

function love.mousepressed(x, y, button, istouch, presses)
    local width, height = love.graphics.getDimensions()
    
    if button == 1 then
        if state == "menu" then
            local bw, bh = 200, 40
            local bx, by = width / 2 - bw / 2, height / 2
            if x > bx and x < bx + bw and y > by and y < by + bh then
                state = "api_list"
                scroll = 0
            end
        elseif state == "api_list" then
            for i, m in ipairs(modules) do
                local my = 60 + (i - 1) * 35 + scroll
                local bx, by, bw, bh = 20, my, 300, 30
                if x > bx and x < bx + bw and y > by and y < by + bh then
                    selected_module = m
                    state = "api_detail"
                    scroll = 0
                    break
                end
            end
        end
    end
end

function love.wheelmoved(x, y)
    if state == "api_list" or state == "api_detail" then
        scroll = scroll + y * 40
        if scroll > 0 then scroll = 0 end
    end
end

function love.keypressed(key)
    if key == "escape" then
        if state == "api_detail" then
            state = "api_list"
            scroll = 0
        elseif state == "api_list" then
            state = "menu"
            scroll = 0
        end
    end
end
