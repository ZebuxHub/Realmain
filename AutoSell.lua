--[[
    AutoSell.lua
    Automatically favorites selected items and sells everything else
    Version: 1.0.0
    Author: Zebux
]]

local AutoSell = {
    Version = "1.0.0",
    
    -- State
    IsRunning = false,
    
    -- Settings
    Settings = {
        AutoSellEnabled = false,
        KeepPlants = {},  -- Array of plant names to keep
        KeepBrainrots = {},  -- Array of brainrot rarities to keep
        MinPlantDamage = 0,  -- Minimum damage for plants (0 = disabled)
    },
    
    -- Dependencies
    Services = nil,
    References = nil,
    Brain = nil,
    
    -- Cached Remotes
    FavoriteRemote = nil,
    SellRemote = nil,
    
    -- Event Connections
    BackpackConnection = nil,
    CharacterConnection = nil,
    
    -- Cached Data
    FavoritedItems = {},  -- Track what we've favorited (by ID)
}

--[[
    ========================================
    Initialization
    ========================================
]]

function AutoSell.Init(services, references, brain)
    AutoSell.Services = services
    AutoSell.References = references
    AutoSell.Brain = brain
    
    -- Cache remotes
    pcall(function()
        AutoSell.FavoriteRemote = AutoSell.Services.ReplicatedStorage
            :WaitForChild("Remotes", 5)
            :WaitForChild("FavoriteItem", 5)
        
        AutoSell.SellRemote = AutoSell.Services.ReplicatedStorage
            :WaitForChild("Remotes", 5)
            :WaitForChild("ItemSell", 5)
    end)
    
    return true
end

--[[
    ========================================
    Data Functions
    ========================================
]]

-- Get all plant names from ReplicatedStorage
function AutoSell.GetAllPlants()
    local plants = {}
    
    pcall(function()
        local plantsFolder = AutoSell.Services.ReplicatedStorage:FindFirstChild("Assets")
        if plantsFolder then
            plantsFolder = plantsFolder:FindFirstChild("Plants")
            if plantsFolder then
                for _, plant in ipairs(plantsFolder:GetChildren()) do
                    table.insert(plants, plant.Name)
                end
            end
        end
    end)
    
    table.sort(plants)
    return plants
end

-- Get all unique brainrot rarities from ReplicatedStorage
function AutoSell.GetAllBrainrotRarities()
    local rarities = {}
    local seen = {}  -- Track duplicates
    
    pcall(function()
        local brainrotsFolder = AutoSell.Services.ReplicatedStorage:FindFirstChild("Assets")
        if brainrotsFolder then
            brainrotsFolder = brainrotsFolder:FindFirstChild("Brainrots")
            if brainrotsFolder then
                for _, brainrot in ipairs(brainrotsFolder:GetChildren()) do
                    -- Get Rarity attribute from each brainrot model
                    local rarity = brainrot:GetAttribute("Rarity")
                    
                    -- Only add if rarity exists and not seen before
                    if rarity and not seen[rarity] then
                        table.insert(rarities, rarity)
                        seen[rarity] = true
                    end
                end
            end
        end
    end)
    
    table.sort(rarities)
    return rarities
end

-- Legacy function for backwards compatibility
function AutoSell.GetAllBrainrots()
    return AutoSell.GetAllBrainrotRarities()
end

--[[
    ========================================
    Item Management
    ========================================
]]

-- Get the base name from tool name (removes prefixes like [Legendary], [1.9 kg])
function AutoSell.GetBaseName(toolName)
    -- Remove prefixes in brackets
    local baseName = toolName:gsub("%b[]%s*", "")
    return baseName:match("^%s*(.-)%s*$")  -- Trim whitespace
end

-- Get brainrot rarity from ReplicatedStorage based on name
function AutoSell.GetBrainrotRarity(toolName)
    local baseName = AutoSell.GetBaseName(toolName)
    
    local rarity = nil
    pcall(function()
        local brainrotsFolder = AutoSell.Services.ReplicatedStorage:FindFirstChild("Assets")
        if brainrotsFolder then
            brainrotsFolder = brainrotsFolder:FindFirstChild("Brainrots")
            if brainrotsFolder then
                local brainrotModel = brainrotsFolder:FindFirstChild(baseName)
                if brainrotModel then
                    rarity = brainrotModel:GetAttribute("Rarity")
                end
            end
        end
    end)
    
    return rarity
end

-- Get plant damage from tool
function AutoSell.GetPlantDamage(tool)
    if not tool then return 0 end
    
    -- Try to get Damage attribute from tool
    local damage = tool:GetAttribute("Damage")
    if damage then return damage end
    
    -- Try to get from Handle
    pcall(function()
        local handle = tool:FindFirstChild("Handle")
        if handle then
            damage = handle:GetAttribute("Damage")
        end
    end)
    
    return damage or 0
end

-- Check if plant name matches keep list
function AutoSell.IsPlantInKeepList(itemName)
    for _, keepName in ipairs(AutoSell.Settings.KeepPlants) do
        if itemName:find(keepName, 1, true) then
            return true
        end
    end
    return false
end

-- Determine if item is a plant or brainrot by checking ReplicatedStorage
function AutoSell.IsPlant(itemName)
    local baseName = AutoSell.GetBaseName(itemName)
    
    local found = false
    pcall(function()
        local plantsFolder = AutoSell.Services.ReplicatedStorage:FindFirstChild("Assets")
        if plantsFolder then
            plantsFolder = plantsFolder:FindFirstChild("Plants")
            if plantsFolder and plantsFolder:FindFirstChild(baseName) then
                found = true
            end
        end
    end)
    
    return found
end

-- Check if item should be kept (plants by name + damage, brainrots by rarity)
function AutoSell.ShouldKeepItem(itemName, itemTool)
    -- First, determine if this is a plant or brainrot
    local isPlant = AutoSell.IsPlant(itemName)
    
    if isPlant then
        -- PLANT: Check by name + optional damage filter
        if AutoSell.IsPlantInKeepList(itemName) then
            -- If MinPlantDamage is set, also check damage
            if AutoSell.Settings.MinPlantDamage > 0 then
                local damage = AutoSell.GetPlantDamage(itemTool)
                -- Only keep if damage >= MinPlantDamage
                if damage >= AutoSell.Settings.MinPlantDamage then
                    return true
                end
                -- Plant matches name but damage too low
                return false
            else
                -- No damage filter, keep all matching plants
                return true
            end
        end
    else
        -- BRAINROT: Check by RARITY (not name)
        if #AutoSell.Settings.KeepBrainrots > 0 then
            local brainrotRarity = AutoSell.GetBrainrotRarity(itemName)
            
            if brainrotRarity then
                for _, keepRarity in ipairs(AutoSell.Settings.KeepBrainrots) do
                    if brainrotRarity == keepRarity then
                        return true
                    end
                end
            end
        end
    end
    
    return false
end

-- Get item ID from tool
function AutoSell.GetItemID(tool)
    if not tool then return nil end
    
    -- Try to get ID attribute
    local id = tool:GetAttribute("ID")
    if id then return id end
    
    -- Try to find ID in tool structure
    pcall(function()
        local handle = tool:FindFirstChild("Handle")
        if handle then
            id = handle:GetAttribute("ID")
        end
    end)
    
    return id
end

-- Favorite an item
function AutoSell.FavoriteItem(tool)
    if not AutoSell.FavoriteRemote or not tool then return false end
    
    local id = AutoSell.GetItemID(tool)
    if not id then return false end
    
    -- Skip if already favorited
    if AutoSell.FavoritedItems[id] then return true end
    
    local success = pcall(function()
        AutoSell.FavoriteRemote:FireServer(id)
    end)
    
    if success then
        AutoSell.FavoritedItems[id] = true
    end
    
    return success
end

-- Favorite all items in keep lists
function AutoSell.FavoriteAllKeepItems()
    local player = AutoSell.References.LocalPlayer
    local backpack = player:FindFirstChild("Backpack")
    local character = player.Character
    
    local itemsToFavorite = {}
    
    -- Check backpack
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and AutoSell.ShouldKeepItem(tool.Name, tool) then
                table.insert(itemsToFavorite, tool)
            end
        end
    end
    
    -- Check character
    if character then
        for _, tool in ipairs(character:GetChildren()) do
            if tool:IsA("Tool") and AutoSell.ShouldKeepItem(tool.Name, tool) then
                table.insert(itemsToFavorite, tool)
            end
        end
    end
    
    -- Favorite all
    for _, tool in ipairs(itemsToFavorite) do
        AutoSell.FavoriteItem(tool)
        task.wait(0.05)  -- Small delay between favorites
    end
    
    return #itemsToFavorite
end

-- Sell all non-favorited items
function AutoSell.SellAllItems()
    if not AutoSell.SellRemote then return false end
    
    -- First, make sure all keep items are favorited
    AutoSell.FavoriteAllKeepItems()
    
    -- Small delay to ensure favorites are processed
    task.wait(0.2)
    
    -- Fire sell remote
    local success = pcall(function()
        AutoSell.SellRemote:FireServer()
    end)
    
    return success
end

--[[
    ========================================
    Event Handling
    ========================================
]]

-- Handle new item added to backpack
function AutoSell.OnItemAdded(tool)
    if not tool:IsA("Tool") then return end
    if not AutoSell.IsRunning or not AutoSell.Settings.AutoSellEnabled then return end
    
    -- Check if we should keep this item (pass tool for rarity checking)
    if AutoSell.ShouldKeepItem(tool.Name, tool) then
        -- Favorite it immediately
        task.defer(function()
            task.wait(0.1)  -- Wait for ID to replicate
            AutoSell.FavoriteItem(tool)
        end)
    else
        -- It's not in keep list, sell after a short delay
        task.defer(function()
            task.wait(0.5)  -- Wait a bit to ensure all favorites are processed
            AutoSell.SellAllItems()
        end)
    end
end

-- Setup event listeners
function AutoSell.SetupEventListeners()
    local player = AutoSell.References.LocalPlayer
    
    -- Listen for backpack changes
    local backpack = player:FindFirstChild("Backpack")
    if backpack and not AutoSell.BackpackConnection then
        AutoSell.BackpackConnection = backpack.ChildAdded:Connect(function(child)
            AutoSell.OnItemAdded(child)
        end)
    end
    
    -- Listen for character respawn
    if not AutoSell.CharacterConnection then
        AutoSell.CharacterConnection = player.CharacterAdded:Connect(function()
            task.wait(1)
            AutoSell.SetupEventListeners()
            
            -- Re-favorite all keep items on respawn
            if AutoSell.IsRunning and AutoSell.Settings.AutoSellEnabled then
                task.wait(2)
                AutoSell.FavoriteAllKeepItems()
            end
        end)
    end
end

-- Cleanup event listeners
function AutoSell.CleanupEventListeners()
    if AutoSell.BackpackConnection then
        AutoSell.BackpackConnection:Disconnect()
        AutoSell.BackpackConnection = nil
    end
    if AutoSell.CharacterConnection then
        AutoSell.CharacterConnection:Disconnect()
        AutoSell.CharacterConnection = nil
    end
end

--[[
    ========================================
    Start/Stop Functions
    ========================================
]]

function AutoSell.Start()
    if AutoSell.IsRunning then return false end
    
    -- Validate remotes
    if not AutoSell.FavoriteRemote or not AutoSell.SellRemote then
        return false
    end
    
    -- Validate settings
    if #AutoSell.Settings.KeepPlants == 0 and #AutoSell.Settings.KeepBrainrots == 0 then
        return false  -- Must have at least one keep item
    end
    
    AutoSell.IsRunning = true
    AutoSell.FavoritedItems = {}  -- Reset cache
    
    -- Setup event listeners
    AutoSell.SetupEventListeners()
    
    -- Immediately favorite all current keep items
    task.spawn(function()
        AutoSell.FavoriteAllKeepItems()
    end)
    
    return true
end

function AutoSell.Stop()
    if not AutoSell.IsRunning then return false end
    
    AutoSell.IsRunning = false
    
    -- Cleanup event listeners
    AutoSell.CleanupEventListeners()
    
    return true
end

--[[
    ========================================
    Status Functions
    ========================================
]]

function AutoSell.GetStatus()
    return {
        IsRunning = AutoSell.IsRunning,
        KeepPlants = #AutoSell.Settings.KeepPlants,
        KeepBrainrots = #AutoSell.Settings.KeepBrainrots,
        FavoritedCount = AutoSell.FavoritedItems and #AutoSell.FavoritedItems or 0,
    }
end

return AutoSell

