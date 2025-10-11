--[[
    🌱 Plant Vs Brainrot - Auto Trade Module
    Automatically gift brainrots/plants to other players
    
    Features:
    - Select target player from live player list
    - Choose item type: Brainrot or Plant
    - Filter by specific brainrot name, mutation, or plant name
    - Continuous gifting until toggle off
    - Efficient scanning and item matching
]]

local AutoTrade = {
    Version = "1.0.0",
    
    -- State
    IsRunning = false,
    TotalGifts = 0,
    AutoAcceptEnabled = false,
    TotalAccepted = 0,
    
    -- Settings
    Settings = {
        AutoTradeEnabled = false,
        AutoAcceptEnabled = false,
        TargetPlayer = "",
        SelectedBrainrots = {},
        SelectedBrainrotMutations = {},
        SelectedPlants = {},
        SelectedPlantMutations = {},
    },
    
    -- Dependencies
    Services = nil,
    References = nil,
    Brain = nil,
    
    -- Cached Data
    GiftRemote = nil,
    AcceptGiftRemote = nil,
    GiftSignalConnection = nil,
    PlayerList = {},
}

--[[
    ========================================
    Initialization
    ========================================
]]

function AutoTrade.Init(services, references, brain)
    AutoTrade.Services = services
    AutoTrade.References = references
    AutoTrade.Brain = brain
    
    -- Cache remotes
    pcall(function()
        AutoTrade.GiftRemote = AutoTrade.Services.ReplicatedStorage
            :WaitForChild("Remotes", 5)
            :WaitForChild("GiftItem", 5)
        
        AutoTrade.AcceptGiftRemote = AutoTrade.Services.ReplicatedStorage
            :WaitForChild("Remotes", 5)
            :WaitForChild("AcceptGift", 5)
    end)
    
    return true
end

--[[
    ========================================
    Helper Functions
    ========================================
]]

-- Get all players (excluding self) - Optimized
function AutoTrade.GetPlayerList()
    local players = {}
    local localPlayer = AutoTrade.References.LocalPlayer
    
    for _, player in ipairs(AutoTrade.Services.Players:GetPlayers()) do
        if player ~= localPlayer then
            players[#players + 1] = player.Name
        end
    end
    
    table.sort(players)  -- Alphabetical order
    return players
end

-- Get all brainrot names - Optimized
function AutoTrade.GetBrainrotList()
    local brainrots = {}
    
    local success = pcall(function()
        local brainrotFolder = AutoTrade.Services.ReplicatedStorage
            :FindFirstChild("Assets")
            :FindFirstChild("Animations")
            :FindFirstChild("Brainrots")
        
        if brainrotFolder then
            for _, brainrot in ipairs(brainrotFolder:GetChildren()) do
                brainrots[#brainrots + 1] = brainrot.Name
            end
        end
    end)
    
    if success then
        table.sort(brainrots)
    end
    
    return brainrots
end

-- Get all mutation names - Optimized
function AutoTrade.GetMutationList()
    local mutations = {}
    
    local success = pcall(function()
        local mutationFolder = AutoTrade.Services.ReplicatedStorage
            :FindFirstChild("MutationRenderer")
            :FindFirstChild("Mutations")
        
        if mutationFolder then
            for _, mutation in ipairs(mutationFolder:GetChildren()) do
                mutations[#mutations + 1] = mutation.Name
            end
        end
    end)
    
    if success then
        table.sort(mutations)
    end
    
    return mutations
end

-- Get all plant names - Optimized
function AutoTrade.GetPlantList()
    local plants = {}
    
    local success = pcall(function()
        local plantFolder = AutoTrade.Services.ReplicatedStorage
            :FindFirstChild("Assets")
            :FindFirstChild("Animations")
            :FindFirstChild("Plants")
        
        if plantFolder then
            for _, plant in ipairs(plantFolder:GetChildren()) do
                plants[#plants + 1] = plant.Name
            end
        end
    end)
    
    if success then
        table.sort(plants)
    end
    
    return plants
end

-- Get all plant mutation names - Optimized
function AutoTrade.GetPlantMutationList()
    local mutations = {}
    
    local success = pcall(function()
        local mutationModule = AutoTrade.Services.ReplicatedStorage
            :FindFirstChild("Modules")
            :FindFirstChild("Library")
            :FindFirstChild("PlantMutations")
        
        if mutationModule then
            local mutationData = require(mutationModule)
            if mutationData and mutationData.Colors then
                for mutationName, _ in pairs(mutationData.Colors) do
                    mutations[#mutations + 1] = mutationName
                end
            end
        end
    end)
    
    if success then
        table.sort(mutations)
    end
    
    return mutations
end

-- Find matching item in backpack or character - Optimized
function AutoTrade.FindMatchingItem()
    local character = AutoTrade.References.LocalPlayer.Character
    local backpack = AutoTrade.References.LocalPlayer:FindFirstChild("Backpack")
    
    if not character and not backpack then return nil end
    
    -- Scan both character and backpack
    local locations = {}
    if character then table.insert(locations, character) end
    if backpack then table.insert(locations, backpack) end
    
    for _, location in ipairs(locations) do
        for _, child in ipairs(location:GetChildren()) do
            if child:IsA("Tool") then
                local itemName = child.Name
                
                -- Priority 1: Plant Mutations (e.g., "Gold Pumpkin")
                for _, mutation in ipairs(AutoTrade.Settings.SelectedPlantMutations) do
                    if itemName:find(mutation) then
                        return child
                    end
                end
                
                -- Priority 2: Brainrot Mutations
                for _, mutation in ipairs(AutoTrade.Settings.SelectedBrainrotMutations) do
                    if itemName:find(mutation) then
                        return child
                    end
                end
                
                -- Priority 3: Plant Names (exact match)
                for _, plantName in ipairs(AutoTrade.Settings.SelectedPlants) do
                    if itemName == plantName then
                        return child
                    end
                end
                
                -- Priority 4: Brainrot Names (substring match)
                for _, brainrotName in ipairs(AutoTrade.Settings.SelectedBrainrots) do
                    if itemName:find(brainrotName) then
                        return child
                    end
                end
            end
        end
    end
    
    return nil
end

-- Move item to character if it's in backpack (for gifting)
function AutoTrade.MoveToCharacter(item)
    if not item then return false end
    
    local character = AutoTrade.References.LocalPlayer.Character
    if not character then return false end
    
    -- If item is already in character, we're good
    if item.Parent == character then
        return true
    end
    
    -- Try to equip the tool
    local success = pcall(function()
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid and item:IsA("Tool") then
            humanoid:EquipTool(item)
        end
    end)
    
    task.wait(0.1) -- Wait for equip
    return item.Parent == character
end


-- Gift item to player - Optimized
function AutoTrade.GiftItem(item, targetPlayer)
    if not item or not targetPlayer or targetPlayer == "" then
        return false
    end
    
    local success = pcall(function()
        if not AutoTrade.GiftRemote then
            AutoTrade.GiftRemote = AutoTrade.Services.ReplicatedStorage
                :WaitForChild("Remotes", 5)
                :WaitForChild("GiftItem", 5)
        end
        
        if AutoTrade.GiftRemote then
            local args = {
                [1] = {
                    ["Item"] = item,
                    ["ToGift"] = targetPlayer
                }
            }
            
            AutoTrade.GiftRemote:FireServer(unpack(args))
            AutoTrade.TotalGifts = AutoTrade.TotalGifts + 1
            return true
        end
    end)
    
    return success
end

--[[
    ========================================
    Main Trade Loop
    ========================================
]]

-- Main gifting loop - Highly optimized
function AutoTrade.TradeLoop()
    task.spawn(function()
        while AutoTrade.IsRunning and AutoTrade.Settings.AutoTradeEnabled do
            local targetPlayer = AutoTrade.Settings.TargetPlayer
            
            -- Validate target player
            if targetPlayer == "" then
                task.wait(1)
                continue
            end
            
            -- Find matching item
            local item = AutoTrade.FindMatchingItem()
            
            if item then
                -- Move item to character first
                local moved = AutoTrade.MoveToCharacter(item)
                
                if moved then
                    -- Gift the item
                    local success = AutoTrade.GiftItem(item, targetPlayer)
                    
                    if success then
                        -- Wait briefly before next check
                        task.wait(0.5)
                    else
                        -- Failed to gift, wait longer
                        task.wait(2)
                    end
                else
                    -- Failed to move item, wait and retry
                    task.wait(1)
                end
            else
                -- No matching item found, wait before retry
                task.wait(1)
            end
        end
    end)
end

--[[
    ========================================
    Start/Stop Functions
    ========================================
]]

function AutoTrade.Start()
    if AutoTrade.IsRunning then return false end
    
    -- Validate settings
    if AutoTrade.Settings.TargetPlayer == "" then
        warn("[AutoTrade] ⚠️ No target player selected!")
        return false
    end
    
    -- Check if at least one item type is selected
    local hasSelection = #AutoTrade.Settings.SelectedPlantMutations > 0
        or #AutoTrade.Settings.SelectedBrainrotMutations > 0
        or #AutoTrade.Settings.SelectedPlants > 0
        or #AutoTrade.Settings.SelectedBrainrots > 0
    
    if not hasSelection then
        warn("[AutoTrade] ⚠️ Please select at least one item to trade!")
        return false
    end
    
    AutoTrade.IsRunning = true
    AutoTrade.TotalGifts = 0
    AutoTrade.TradeLoop()
    
    return true
end

function AutoTrade.Stop()
    if not AutoTrade.IsRunning then return false end
    
    AutoTrade.IsRunning = false
    return true
end

--[[
    ========================================
    Auto Accept Functions
    ========================================
]]

-- Auto accept incoming gifts
function AutoTrade.StartAutoAccept()
    if AutoTrade.AutoAcceptEnabled then return false end
    
    -- Validate remote
    if not AutoTrade.GiftRemote then
        pcall(function()
            AutoTrade.GiftRemote = AutoTrade.Services.ReplicatedStorage
                :WaitForChild("Remotes", 5)
                :WaitForChild("GiftItem", 5)
        end)
    end
    
    if not AutoTrade.AcceptGiftRemote then
        pcall(function()
            AutoTrade.AcceptGiftRemote = AutoTrade.Services.ReplicatedStorage
                :WaitForChild("Remotes", 5)
                :WaitForChild("AcceptGift", 5)
        end)
    end
    
    if not AutoTrade.GiftRemote or not AutoTrade.AcceptGiftRemote then
        warn("[AutoTrade] ⚠️ Failed to find gift remotes!")
        return false
    end
    
    -- Listen for incoming gifts
    AutoTrade.GiftSignalConnection = AutoTrade.GiftRemote.OnClientEvent:Connect(function(data)
        if not AutoTrade.AutoAcceptEnabled then return end
        
        -- Validate data
        if not data or type(data) ~= "table" then return end
        if not data.ID then return end
        
        -- Auto accept the gift
        task.spawn(function()
            local success = pcall(function()
                local args = {
                    [1] = {
                        ["ID"] = data.ID
                    }
                }
                AutoTrade.AcceptGiftRemote:FireServer(unpack(args))
                AutoTrade.TotalAccepted = AutoTrade.TotalAccepted + 1
            end)
        end)
    end)
    
    AutoTrade.AutoAcceptEnabled = true
    return true
end

function AutoTrade.StopAutoAccept()
    if not AutoTrade.AutoAcceptEnabled then return false end
    
    -- Disconnect signal
    if AutoTrade.GiftSignalConnection then
        AutoTrade.GiftSignalConnection:Disconnect()
        AutoTrade.GiftSignalConnection = nil
    end
    
    AutoTrade.AutoAcceptEnabled = false
    return true
end

--[[
    ========================================
    Status Functions
    ========================================
]]

function AutoTrade.GetStatus()
    -- Count total selected items
    local totalSelected = #AutoTrade.Settings.SelectedPlantMutations
        + #AutoTrade.Settings.SelectedBrainrotMutations
        + #AutoTrade.Settings.SelectedPlants
        + #AutoTrade.Settings.SelectedBrainrots
    
    return {
        IsRunning = AutoTrade.IsRunning,
        TotalGifts = AutoTrade.TotalGifts,
        TargetPlayer = AutoTrade.Settings.TargetPlayer,
        TotalSelected = totalSelected,
        AutoAcceptEnabled = AutoTrade.AutoAcceptEnabled,
        TotalAccepted = AutoTrade.TotalAccepted
    }
end

return AutoTrade

