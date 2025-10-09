--[[
    ========================================
    AutoPlace Module 🌱
    ========================================
    Handles automatic seed and plant placement
    Event-driven and optimized for performance
--]]

local AutoPlace = {
    Version = "1.0.0",
    
    -- State
    IsRunning = false,
    IsSeedPlacementActive = false,
    IsPlantPlacementActive = false,
    
    -- Stats
    TotalSeedsPlaced = 0,
    TotalPlantsPlaced = 0,
    
    -- Dependencies (Set by Main.lua)
    Services = {},
    References = {},
    Settings = {},
    Brain = {},
    
    -- Connections
    BackpackConnection = nil,
    PlotConnection = nil
}

--[[
    ========================================
    Initialization
    ========================================
--]]

function AutoPlace.Init(services, references, settings, brain)
    AutoPlace.Services = services
    AutoPlace.References = references
    AutoPlace.Settings = settings
    AutoPlace.Brain = brain
    
    print("✅ [AutoPlace] Module initialized successfully!")
    return true
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

-- Generate unique ID for placement
local function GenerateID()
    local HttpService = AutoPlace.Services.HttpService
    return HttpService:GenerateGUID(false)
end

-- Get all seeds from ReplicatedStorage
function AutoPlace.GetAllSeeds()
    local seedList = {}
    local Seeds = AutoPlace.References.Seeds
    
    for _, seedInstance in ipairs(Seeds:GetChildren()) do
        local hidden = seedInstance:GetAttribute("Hidden")
        if not hidden then
            table.insert(seedList, seedInstance.Name)
        end
    end
    
    table.sort(seedList)
    return seedList
end

-- Get all plants from ReplicatedStorage with damage info
function AutoPlace.GetAllPlants()
    local plantList = {}
    local Plants = AutoPlace.References.Plants
    
    for _, plantInstance in ipairs(Plants:GetChildren()) do
        local damage = plantInstance:GetAttribute("Damage") or 0
        table.insert(plantList, {
            Name = plantInstance.Name,
            Damage = damage
        })
    end
    
    -- Sort by damage (highest first)
    table.sort(plantList, function(a, b)
        return a.Damage > b.Damage
    end)
    
    return plantList
end

-- Get player's plot number
function AutoPlace.GetPlayerPlotNumber()
    local LocalPlayer = AutoPlace.References.LocalPlayer
    local plotNumber = LocalPlayer:GetAttribute("Plot")
    return plotNumber
end

-- Get player's plot
function AutoPlace.GetPlayerPlot()
    local plotNumber = AutoPlace.GetPlayerPlotNumber()
    if not plotNumber then
        return nil
    end
    
    local Plots = AutoPlace.References.Plots
    local plot = Plots:FindFirstChild(tostring(plotNumber))
    return plot
end

-- Get all available grass slots in player's plot
function AutoPlace.GetAvailableSlots()
    local slots = {}
    local plot = AutoPlace.GetPlayerPlot()
    
    if not plot then
        return slots
    end
    
    local Rows = plot:FindFirstChild("Rows")
    if not Rows then
        return slots
    end
    
    for _, row in ipairs(Rows:GetChildren()) do
        local Grass = row:FindFirstChild("Grass")
        if Grass then
            for _, slot in ipairs(Grass:GetChildren()) do
                local canPlace = slot:GetAttribute("CanPlace")
                if canPlace then
                    table.insert(slots, {
                        Slot = slot,
                        Row = row.Name,
                        CFrame = slot.CFrame
                    })
                end
            end
        end
    end
    
    return slots
end

-- Get item from backpack by name
function AutoPlace.GetItemFromBackpack(itemName)
    local Backpack = AutoPlace.References.LocalPlayer.Backpack
    return Backpack:FindFirstChild(itemName)
end

-- Get all plants from backpack
function AutoPlace.GetPlantsFromBackpack()
    local plants = {}
    local Backpack = AutoPlace.References.LocalPlayer.Backpack
    
    for _, item in ipairs(Backpack:GetChildren()) do
        if item:IsA("Model") or item:IsA("Tool") then
            -- Check if it exists in Plants folder
            local plantAsset = AutoPlace.References.Plants:FindFirstChild(item.Name)
            if plantAsset then
                local damage = plantAsset:GetAttribute("Damage") or 0
                table.insert(plants, {
                    Item = item,
                    Name = item.Name,
                    Damage = damage
                })
            end
        end
    end
    
    return plants
end

--[[
    ========================================
    Placement Functions
    ========================================
--]]

-- Place a seed at a specific slot
function AutoPlace.PlaceSeed(seedName, slot)
    local success, err = pcall(function()
        local args = {
            [1] = {
                ["ID"] = GenerateID(),
                ["CFrame"] = slot.CFrame,
                ["Item"] = seedName,
                ["Floor"] = slot
            }
        }
        
        AutoPlace.References.PlaceItemRemote:FireServer(unpack(args))
        AutoPlace.TotalSeedsPlaced = AutoPlace.TotalSeedsPlaced + 1
        print("[AutoPlace] Placed seed:", seedName, "| Total:", AutoPlace.TotalSeedsPlaced)
        return true
    end)
    
    if not success then
        warn("[AutoPlace] Failed to place seed:", err)
        return false
    end
    
    return success
end

-- Place a plant at a specific slot
function AutoPlace.PlacePlant(plantName, slot)
    local success, err = pcall(function()
        local args = {
            [1] = {
                ["ID"] = GenerateID(),
                ["CFrame"] = slot.CFrame,
                ["Item"] = plantName,
                ["Floor"] = slot
            }
        }
        
        AutoPlace.References.PlaceItemRemote:FireServer(unpack(args))
        AutoPlace.TotalPlantsPlaced = AutoPlace.TotalPlantsPlaced + 1
        
        -- Get plant damage for logging
        local plantAsset = AutoPlace.References.Plants:FindFirstChild(plantName)
        local damage = plantAsset and plantAsset:GetAttribute("Damage") or 0
        
        print("[AutoPlace] Placed plant:", plantName, "| DMG:", FormatNumber(damage), "| Total:", AutoPlace.TotalPlantsPlaced)
        return true
    end)
    
    if not success then
        warn("[AutoPlace] Failed to place plant:", err)
        return false
    end
    
    return success
end

--[[
    ========================================
    Auto Placement Logic
    ========================================
--]]

-- Auto place seeds
function AutoPlace.ProcessSeedPlacement()
    if not AutoPlace.IsSeedPlacementActive then
        return
    end
    
    local selectedSeed = AutoPlace.Settings.SelectedPlaceSeed
    if not selectedSeed then
        return
    end
    
    -- Get available slots
    local slots = AutoPlace.GetAvailableSlots()
    if #slots == 0 then
        return
    end
    
    -- Check if seed exists in backpack
    local seedItem = AutoPlace.GetItemFromBackpack(selectedSeed)
    if not seedItem then
        return
    end
    
    -- Place seed at first available slot
    local slot = slots[1].Slot
    AutoPlace.PlaceSeed(selectedSeed, slot)
end

-- Auto place plants
function AutoPlace.ProcessPlantPlacement()
    if not AutoPlace.IsPlantPlacementActive then
        return
    end
    
    -- Get available slots
    local slots = AutoPlace.GetAvailableSlots()
    if #slots == 0 then
        return
    end
    
    -- Get all plants from backpack
    local plants = AutoPlace.GetPlantsFromBackpack()
    if #plants == 0 then
        return
    end
    
    local selectedPlant = AutoPlace.Settings.SelectedPlacePlant
    local damageFilter = AutoPlace.Settings.PlantDamageFilter or 0
    
    -- Place plants
    for _, plantData in ipairs(plants) do
        if #slots == 0 then
            break
        end
        
        local shouldPlace = false
        
        -- Check if matches selected plant
        if selectedPlant and plantData.Name == selectedPlant then
            shouldPlace = true
        -- Or check if damage meets filter
        elseif plantData.Damage >= damageFilter then
            shouldPlace = true
        end
        
        if shouldPlace then
            local slot = table.remove(slots, 1)
            AutoPlace.PlacePlant(plantData.Name, slot.Slot)
            task.wait(0.1) -- Small delay between placements
        end
    end
end

--[[
    ========================================
    Event-Driven System
    ========================================
--]]

function AutoPlace.SetupEventListeners()
    -- Disconnect old connections
    if AutoPlace.BackpackConnection then
        AutoPlace.BackpackConnection:Disconnect()
        AutoPlace.BackpackConnection = nil
    end
    
    if AutoPlace.PlotConnection then
        AutoPlace.PlotConnection:Disconnect()
        AutoPlace.PlotConnection = nil
    end
    
    -- Listen for backpack changes (when seeds/plants are added)
    local Backpack = AutoPlace.References.LocalPlayer.Backpack
    AutoPlace.BackpackConnection = Backpack.ChildAdded:Connect(function(item)
        if not AutoPlace.IsRunning then
            return
        end
        
        -- Check if it's a seed or plant
        local isSeed = AutoPlace.References.Seeds:FindFirstChild(item.Name)
        local isPlant = AutoPlace.References.Plants:FindFirstChild(item.Name)
        
        if isSeed and AutoPlace.IsSeedPlacementActive then
            task.wait(0.2) -- Wait for item to fully load
            AutoPlace.ProcessSeedPlacement()
        elseif isPlant and AutoPlace.IsPlantPlacementActive then
            task.wait(0.2) -- Wait for item to fully load
            AutoPlace.ProcessPlantPlacement()
        end
    end)
    
    print("[AutoPlace] Event listeners setup complete!")
end

--[[
    ========================================
    Control Functions
    ========================================
--]]

function AutoPlace.Start()
    if AutoPlace.IsRunning then
        print("[AutoPlace] Already running!")
        return
    end
    
    AutoPlace.IsRunning = true
    AutoPlace.SetupEventListeners()
    
    print("[AutoPlace] System started!")
end

function AutoPlace.Stop()
    if not AutoPlace.IsRunning then
        return
    end
    
    AutoPlace.IsRunning = false
    AutoPlace.IsSeedPlacementActive = false
    AutoPlace.IsPlantPlacementActive = false
    
    -- Disconnect listeners
    if AutoPlace.BackpackConnection then
        AutoPlace.BackpackConnection:Disconnect()
        AutoPlace.BackpackConnection = nil
    end
    
    if AutoPlace.PlotConnection then
        AutoPlace.PlotConnection:Disconnect()
        AutoPlace.PlotConnection = nil
    end
    
    print("[AutoPlace] System stopped!")
end

function AutoPlace.StartSeedPlacement()
    AutoPlace.IsSeedPlacementActive = true
    print("[AutoPlace] Seed placement ENABLED")
    
    -- Try to place immediately if items available
    task.spawn(function()
        AutoPlace.ProcessSeedPlacement()
    end)
end

function AutoPlace.StopSeedPlacement()
    AutoPlace.IsSeedPlacementActive = false
    print("[AutoPlace] Seed placement DISABLED")
end

function AutoPlace.StartPlantPlacement()
    AutoPlace.IsPlantPlacementActive = true
    print("[AutoPlace] Plant placement ENABLED")
    
    -- Try to place immediately if items available
    task.spawn(function()
        AutoPlace.ProcessPlantPlacement()
    end)
end

function AutoPlace.StopPlantPlacement()
    AutoPlace.IsPlantPlacementActive = false
    print("[AutoPlace] Plant placement DISABLED")
end

function AutoPlace.GetStatus()
    return {
        IsRunning = AutoPlace.IsRunning,
        IsSeedPlacementActive = AutoPlace.IsSeedPlacementActive,
        IsPlantPlacementActive = AutoPlace.IsPlantPlacementActive,
        TotalSeedsPlaced = AutoPlace.TotalSeedsPlaced,
        TotalPlantsPlaced = AutoPlace.TotalPlantsPlaced
    }
end

return AutoPlace

