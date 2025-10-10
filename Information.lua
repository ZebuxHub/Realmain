--[[
    🌱 Plant Vs Brainrot - Information Module
    This module handles all information display logic
    
    The Main script is the Brain 🧠 that controls this module!
--]]

local Information = {}

--[[
    ========================================
    Module Configuration
    ========================================
--]]

Information.Version = "1.0.0"

--[[
    ========================================
    Dependencies (Set by Main)
    ========================================
--]]

Information.Services = {
    Players = nil,
    ReplicatedStorage = nil,
    HttpService = nil
}

Information.References = {
    LocalPlayer = nil,
    Seeds = nil,
    Gears = nil
}

Information.Brain = nil
Information.AutoBuy = nil

--[[
    ========================================
    Initialize Module
    ========================================
--]]

function Information.Init(services, references, brain, autoBuy)
    Information.Services = services
    Information.References = references
    Information.Brain = brain
    Information.AutoBuy = autoBuy
    
    print("✅ [Information] Module initialized!")
end

--[[
    ========================================
    Helper Functions
    ========================================
--]]

-- Format numbers with suffixes (1K, 1M, 1B, etc.)
local function FormatNumber(num)
    if num >= 1000000000000 then
        return string.format("%.2fT", num / 1000000000000)
    elseif num >= 1000000000 then
        return string.format("%.2fB", num / 1000000000)
    elseif num >= 1000000 then
        return string.format("%.2fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.2fK", num / 1000)
    else
        return tostring(math.floor(num))
    end
end

--[[
    ========================================
    UI Creation Functions
    ========================================
--]]

-- Create Money Display Section
function Information.CreateMoneyDisplay(infoTab)
    local form = infoTab:PageSection({ 
        Title = "Your Balance",
        Subtitle = "Current money"
    }):Form()
    
    local row = form:Row()
    
    row:Left():TitleStack({
        Title = "Money",
        Subtitle = "Your current balance",
    })
    
    Information.Brain.UI.MoneyLabel = row:Right():Label({
        Text = "$0"
    })
    
    -- Brain: Update money every 0.5 seconds
    task.spawn(function()
        while task.wait(0.5) do
            Information.Brain.UpdateMoney()
        end
    end)
end

-- Create Seed Details Section
function Information.CreateSeedDetails(infoTab)
    local form = infoTab:PageSection({ 
        Title = "Seed Details",
        Subtitle = "Real-time price and stock from UI"
    }):Form()
    
    -- Get all seeds from AutoBuy (loaded from GitHub)
    local seedList = Information.AutoBuy.GetAllSeeds()
    
    -- Store seed info labels for updates
    Information.Brain.UI.SeedInfoLabels = {}
    
    for _, seedName in ipairs(seedList) do
        -- Get seed info with UI-based stock reading (directly read price & stock)
        local seedInstance = Information.References.Seeds:FindFirstChild(seedName)
        if not seedInstance then continue end
        
        local seedInfo = Information.AutoBuy.GetSeedInfo(seedInstance)
        local seedPrice = seedInfo.Price
        local seedStock = seedInfo.Stock
        
        -- Create first row for seed info
        local row1 = form:Row()
        
        row1:Left():TitleStack({
            Title = seedName,
            Subtitle = "Plant: " .. seedInfo.Plant,
        })
        
        local infoLabel = row1:Right():Label({
            Text = "$" .. FormatNumber(seedPrice) .. " | Stock: " .. FormatNumber(seedStock)
        })
        
        -- Create second row for buy button
        local row2 = form:Row()
        
        row2:Left():Label({
            Text = "" -- Empty left side
        })
        
        row2:Right():Button({
            Label = "Buy " .. seedName,
            State = "Primary",
            Pushed = function(self)
                local currentMoney = Information.AutoBuy.GetMoney()
                local currentSeedInfo = Information.AutoBuy.GetSeedInfo(seedInstance)
                local currentStock = currentSeedInfo.Stock
                local currentPrice = currentSeedInfo.Price
                
                if currentMoney >= currentPrice and currentStock > 0 then
                    print("💰 [Brain] Buying " .. seedName .. "...")
                    local success = Information.AutoBuy.PurchaseSeed(seedName)
                    
                    if success then
                        print("✅ Purchased: " .. seedName)
                        
                        -- Immediately update the display
                        task.wait(0.2)  -- Wait for server response
                        local updatedInfo = Information.AutoBuy.GetSeedInfo(seedInstance)
                        local updatedPrice = updatedInfo.Price
                        local updatedStock = updatedInfo.Stock
                        infoLabel.Text = "$" .. FormatNumber(updatedPrice) .. " | Stock: " .. FormatNumber(updatedStock)
                        
                        Information.Brain.UpdateMoney()
                    else
                        print("❌ Failed to buy " .. seedName)
                    end
                elseif currentStock <= 0 then
                    print("⚠️ " .. seedName .. " is out of stock!")
                else
                    print("⚠️ Not enough money for " .. seedName .. "! Need: $" .. FormatNumber(currentPrice))
                end
            end,
        })
        
        -- Brain: Store label reference for real-time updates
        Information.Brain.UI.SeedInfoLabels[seedName] = infoLabel
    end
    
    -- Brain: Update seed info every 0.3 seconds (faster for better UX)
    task.spawn(function()
        while task.wait(0.3) do
            -- Update seed info
            for seedName, label in pairs(Information.Brain.UI.SeedInfoLabels) do
                local seedInstance = Information.References.Seeds:FindFirstChild(seedName)
                
                if seedInstance and label then
                    local seedInfo = Information.AutoBuy.GetSeedInfo(seedInstance)
                    local seedPrice = seedInfo.Price
                    local seedStock = seedInfo.Stock
                    label.Text = "$" .. FormatNumber(seedPrice) .. " | Stock: " .. FormatNumber(seedStock)
                end
            end
        end
    end)
end

-- Create Gear Details Section
function Information.CreateGearDetails(infoTab)
    local form = infoTab:PageSection({ 
        Title = "Gear Details",
        Subtitle = "Real-time price and stock from UI"
    }):Form()
    
    -- Get all gears from AutoBuy (loaded from GitHub)
    local gearList = Information.AutoBuy.GetAllGears()
    
    -- Store gear info labels for updates
    Information.Brain.UI.GearInfoLabels = {}
    
    for _, gearName in ipairs(gearList) do
        -- Get gear info with UI-based stock reading
        local gearPrice = Information.AutoBuy.GetGearPrice(gearName)
        local gearStock = Information.AutoBuy.GetGearStock(gearName)
        
        -- Create first row for gear info
        local row1 = form:Row()
        
        row1:Left():TitleStack({
            Title = gearName,
            Subtitle = "Gear",
        })
        
        local infoLabel = row1:Right():Label({
            Text = "$" .. FormatNumber(gearPrice) .. " | Stock: " .. FormatNumber(gearStock)
        })
        
        -- Create second row for buy button
        local row2 = form:Row()
        
        row2:Left():Label({
            Text = "" -- Empty left side
        })
        
        row2:Right():Button({
            Label = "Buy " .. gearName,
            State = "Primary",
            Pushed = function(self)
                local currentMoney = Information.AutoBuy.GetMoney()
                local currentStock = Information.AutoBuy.GetGearStock(gearName)
                local currentPrice = Information.AutoBuy.GetGearPrice(gearName)
                
                if currentMoney >= currentPrice and currentStock > 0 then
                    print("💰 [Brain] Buying " .. gearName .. "...")
                    local success = Information.AutoBuy.PurchaseGear(gearName)
                    
                    if success then
                        print("✅ Purchased: " .. gearName)
                        
                        -- Immediately update the display
                        task.wait(0.2)  -- Wait for server response
                        local updatedPrice = Information.AutoBuy.GetGearPrice(gearName)
                        local updatedStock = Information.AutoBuy.GetGearStock(gearName)
                        infoLabel.Text = "$" .. FormatNumber(updatedPrice) .. " | Stock: " .. FormatNumber(updatedStock)
                        
                        Information.Brain.UpdateMoney()
                    else
                        print("❌ Failed to buy " .. gearName)
                    end
                elseif currentStock <= 0 then
                    print("⚠️ " .. gearName .. " is out of stock!")
                else
                    print("⚠️ Not enough money for " .. gearName .. "! Need: $" .. FormatNumber(currentPrice))
                end
            end,
        })
        
        -- Brain: Store label reference for real-time updates
        Information.Brain.UI.GearInfoLabels[gearName] = infoLabel
    end
    
    -- Brain: Update gear info every 0.3 seconds (faster for better UX)
    task.spawn(function()
        while task.wait(0.3) do
            -- Update gear info
            for gearName, label in pairs(Information.Brain.UI.GearInfoLabels) do
                if label then
                    local gearPrice = Information.AutoBuy.GetGearPrice(gearName)
                    local gearStock = Information.AutoBuy.GetGearStock(gearName)
                    label.Text = "$" .. FormatNumber(gearPrice) .. " | Stock: " .. FormatNumber(gearStock)
                end
            end
        end
    end)
end

--[[
    ========================================
    Main Setup Function
    ========================================
--]]

function Information.Setup(infoTab)
    print("📊 [Information] Setting up Information tab...")
    
    -- Create all sections
    Information.CreateMoneyDisplay(infoTab)
    Information.CreateSeedDetails(infoTab)
    Information.CreateGearDetails(infoTab)
    
    print("✅ [Information] Information tab setup complete!")
end

--[[
    ========================================
    Return Module
    ========================================
--]]

print("✅ [Information] Module loaded successfully!")

return Information

