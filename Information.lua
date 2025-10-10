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
    
    for _, seedName in ipairs(seedList) do
        local seedInstance = Information.References.Seeds:FindFirstChild(seedName)
        
        if seedInstance then
            -- Get seed info with UI-based stock reading
            local seedInfo = Information.AutoBuy.GetSeedInfo(seedInstance)
            
            -- Create a row for each seed
            local row = form:Row()
            
            row:Left():TitleStack({
                Title = seedName,
                Subtitle = "Plant: " .. seedInfo.Plant,
            })
            
            local infoLabel = row:Right():Label({
                Text = "$" .. FormatNumber(seedInfo.Price) .. " | Stock: " .. FormatNumber(seedInfo.Stock)
            })
            
            -- Add Buy Button
            row:Right():Button({
                Label = "Buy",
                State = "Primary",
                Pushed = function(self)
                    local currentMoney = Information.AutoBuy.GetMoney()
                    local currentSeedInfo = Information.AutoBuy.GetSeedInfo(seedInstance)
                    
                    if currentMoney >= currentSeedInfo.Price and currentSeedInfo.Stock > 0 then
                        print("💰 [Brain] Buying " .. seedName .. "...")
                        local success = Information.AutoBuy.PurchaseSeed(seedName)
                        
                        if success then
                            print("✅ Purchased: " .. seedName)
                            task.wait(0.1)
                            Information.Brain.UpdateMoney()
                        else
                            print("❌ Failed to buy " .. seedName)
                        end
                    elseif currentSeedInfo.Stock <= 0 then
                        print("⚠️ " .. seedName .. " is out of stock!")
                    else
                        print("⚠️ Not enough money for " .. seedName .. "! Need: $" .. FormatNumber(currentSeedInfo.Price))
                    end
                end,
            })
            
            -- Brain: Store label reference for real-time updates
            Information.Brain.UI.SeedInfoLabels[seedName] = infoLabel
        end
    end
    
    -- Brain: Update seed info every 0.3 seconds (faster for better UX)
    task.spawn(function()
        while task.wait(0.3) do
            Information.Brain.UpdateSeedInfo()
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
        
        -- Create a row for each gear
        local row = form:Row()
        
        row:Left():TitleStack({
            Title = gearName,
            Subtitle = "Gear",
        })
        
        local infoLabel = row:Right():Label({
            Text = "$" .. FormatNumber(gearPrice) .. " | Stock: " .. FormatNumber(gearStock)
        })
        
        -- Add Buy Button
        row:Right():Button({
            Label = "Buy",
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
                        task.wait(0.1)
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

