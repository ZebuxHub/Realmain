--[[
    ========================================
    AutoPlace Module - Plant Vs Brainrot
    ========================================
    Handles automatic seed and plant placement
    - Event-driven placement when items added to backpack
    - Finds available plots and rows automatically
    - Filters plants by damage threshold
]]

local AutoPlace = {
    Version = "1.0.0",
    IsRunning = false,
    
    -- Stats
    TotalSeedsPlaced = 0,
    TotalPlantsPlaced = 0,
    
    -- Connections
    BackpackConnection = nil,
    SeedPlacementEnabled = false,
    PlantPlacementEnabled = false,
    
    -- Dependencies (set by Main.lua)
    Services = nil,
    References = nil,
    Settings = nil,
    Brain = nil
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
local function GenerateUUID()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

-- Get all seeds
function AutoPlace.GetAllSeeds()
    local seedList = {}
    
    for _, seedInstance in ipairs(AutoPlace.References.Seeds:GetChildren()) do
        local hidden = seedInstance:GetAttribute("Hidden")
        if not hidden then
            table.insert(seedList, seedInstance.Name)
        end
    end
    
    table.sort(seedList)
    return seedList
end

-- Get all plants with their damage values
function AutoPlace.GetAllPlants()
    local plantList = {}
    
    for _, plantInstance in ipairs(AutoPlace.References.Plants:GetChildren()) do
        local damage = plantInstance:GetAttribute("Damage") or 0
        table.insert(plantList, {
            Name = plantInstance.Name,
            Damage = damage,
            Instance = plantInstance
        })
    end
    
    -- Sort by damage (highest first)
    table.sort(plantList, function(a, b)
        return a.Damage > b.Damage
    end)
    
    return plantList
end

-- Get player's owned plots
function AutoPlace.GetOwnedPlots()
    local ownedPlots = {}
    local plotAttribute = AutoPlace.References.LocalPlayer:GetAttribute("Plot")
    
    if plotAttribute then
        -- If Plot is a single number
        if type(plotAttribute) == "number" then
            table.insert(ownedPlots, tostring(plotAttribute))
        -- If Plot is a string or table
        elseif type(plotAttribute) == "string" then
            table.insert(ownedPlots, plotAttribute)
        end
    end
    
    return ownedPlots
end

-- Find available floor in owned plots
function AutoPlace.FindAvailableFloor()
    local plots = AutoPlace.GetOwnedPlots()
    
    for _, plotId in ipairs(plots) do
        local plot = AutoPlace.References.Plots:FindFirstChild(plotId)
        
        if plot then
            local rows = plot:FindFirstChild("Rows")
            
            if rows then
                for _, row in ipairs(rows:GetChildren()) do
                    local grass = row:FindFirstChild("Grass")
                    
                    if grass then
                        for _, floor in ipairs(grass:GetChildren()) do
                            local canPlace = floor:GetAttribute("CanPlace")
                            
                            if canPlace then
                                return floor
                            end
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

-- Get item from backpack
function AutoPlace.GetItemFromBackpack(itemName)
    return AutoPlace.References.Backpack:FindFirstChild(itemName)
end

-- Get plant info from backpack model
function AutoPlace.GetPlantInfoFromModel(model)
    if not model then return nil end
    
    -- Try to find plant data
    local plantInstance = AutoPlace.References.Plants:FindFirstChild(model.Name)
    if plantInstance then
        return {
            Name = model.Name,
            Damage = plantInstance:GetAttribute("Damage") or 0,
            Model = model
        }
    end
    
    return nil
end

--[[
    ========================================
    Placement Logic
    ========================================
--]]

-- Place a seed
function AutoPlace.PlaceSeed(seedName)
    local floor = AutoPlace.FindAvailableFloor()
    
    if not floor then
        print("[AutoPlace] No available floor found")
        return false
    end
    
    -- Get floor position
    local floorPos = floor.Position
    local cframe = CFrame.new(floorPos.X, floorPos.Y + 1, floorPos.Z)
    
    local args = {
        [1] = {
            ["ID"] = GenerateUUID(),
            ["CFrame"] = cframe,
            ["Item"] = seedName,
            ["Floor"] = floor
        }
    }
    
    local success, err = pcall(function()
        AutoPlace.References.PlaceItemRemote:FireServer(unpack(args))
    end)
    
    if success then
        AutoPlace.TotalSeedsPlaced = AutoPlace.TotalSeedsPlaced + 1
        print("[AutoPlace] Placed seed:", seedName)
        return true
    else
        print("[AutoPlace] Failed to place seed:", err)
        return false
    end
end

-- Place a plant
function AutoPlace.PlacePlant(plantName)
    local floor = AutoPlace.FindAvailableFloor()
    
    if not floor then
        print("[AutoPlace] No available floor found")
        return false
    end
    
    -- Get floor position
    local floorPos = floor.Position
    local cframe = CFrame.new(floorPos.X, floorPos.Y + 1, floorPos.Z)
    
    local args = {
        [1] = {
            ["ID"] = GenerateUUID(),
            ["CFrame"] = cframe,
            ["Item"] = plantName,
            ["Floor"] = floor
        }
    }
    
    local success, err = pcall(function()
        AutoPlace.References.PlaceItemRemote:FireServer(unpack(args))
    end)
    
    if success then
        AutoPlace.TotalPlantsPlaced = AutoPlace.TotalPlantsPlaced + 1
        print("[AutoPlace] Placed plant:", plantName)
        return true
    else
        print("[AutoPlace] Failed to place plant:", err)
        return false
    end
end

-- Check if plant meets damage filter
function AutoPlace.MeetsDamageFilter(plantName)
    local plantInstance = AutoPlace.References.Plants:FindFirstChild(plantName)
    
    if not plantInstance then
        return false
    end
    
    local damage = plantInstance:GetAttribute("Damage") or 0
    return damage >= AutoPlace.Settings.PlantDamageFilter
end

-- Check if should place this seed
function AutoPlace.ShouldPlaceSeed(seedName)
    if not AutoPlace.Settings.SelectedPlaceSeed then
        return true -- Place any seed if none selected
    end
    
    return seedName == AutoPlace.Settings.SelectedPlaceSeed
end

-- Check if should place this plant
function AutoPlace.ShouldPlacePlant(plantName)
    -- Check damage filter first
    if not AutoPlace.MeetsDamageFilter(plantName) then
        return false
    end
    
    -- If specific plant selected, only place that one
    if AutoPlace.Settings.SelectedPlacePlant then
        return plantName == AutoPlace.Settings.SelectedPlacePlant
    end
    
    return true
end

--[[
    ========================================
    Backpack Monitoring
    ========================================
--]]

function AutoPlace.OnBackpackItemAdded(item)
    if not item:IsA("Model") then
        return
    end
    
    -- Check if it's a seed (starts with seed name)
    local isSeed = AutoPlace.References.Seeds:FindFirstChild(item.Name) ~= nil
    
    if isSeed and AutoPlace.SeedPlacementEnabled then
        if AutoPlace.ShouldPlaceSeed(item.Name) then
            task.spawn(function()
                task.wait(0.1) -- Small delay to ensure it's in backpack
                AutoPlace.PlaceSeed(item.Name)
            end)
        end
    end
    
    -- Check if it's a plant
    local plantInfo = AutoPlace.GetPlantInfoFromModel(item)
    
    if plantInfo and AutoPlace.PlantPlacementEnabled then
        if AutoPlace.ShouldPlacePlant(plantInfo.Name) then
            task.spawn(function()
                task.wait(0.1) -- Small delay to ensure it's in backpack
                AutoPlace.PlacePlant(plantInfo.Name)
            end)
        end
    end
end

function AutoPlace.SetupBackpackMonitoring()
    -- Disconnect old connection
    if AutoPlace.BackpackConnection then
        AutoPlace.BackpackConnection:Disconnect()
        AutoPlace.BackpackConnection = nil
    end
    
    -- Listen for items added to backpack
    AutoPlace.BackpackConnection = AutoPlace.References.Backpack.ChildAdded:Connect(function(item)
        AutoPlace.OnBackpackItemAdded(item)
    end)
    
    print("[AutoPlace] Backpack monitoring started")
end

--[[
    ========================================
    Control Functions
    ========================================
--]]

function AutoPlace.Start()
    if AutoPlace.IsRunning then
        print("[AutoPlace] Already running")
        return
    end
    
    AutoPlace.IsRunning = true
    AutoPlace.SetupBackpackMonitoring()
    
    print("[AutoPlace] System started")
end

function AutoPlace.Stop()
    if not AutoPlace.IsRunning then
        print("[AutoPlace] Not running")
        return
    end
    
    AutoPlace.IsRunning = false
    AutoPlace.SeedPlacementEnabled = false
    AutoPlace.PlantPlacementEnabled = false
    
    -- Disconnect backpack monitoring
    if AutoPlace.BackpackConnection then
        AutoPlace.BackpackConnection:Disconnect()
        AutoPlace.BackpackConnection = nil
    end
    
    print("[AutoPlace] System stopped")
end

function AutoPlace.StartSeedPlacement()
    AutoPlace.SeedPlacementEnabled = true
    print("[AutoPlace] Seed placement enabled")
end

function AutoPlace.StopSeedPlacement()
    AutoPlace.SeedPlacementEnabled = false
    print("[AutoPlace] Seed placement disabled")
end

function AutoPlace.StartPlantPlacement()
    AutoPlace.PlantPlacementEnabled = true
    print("[AutoPlace] Plant placement enabled")
end

function AutoPlace.StopPlantPlacement()
    AutoPlace.PlantPlacementEnabled = false
    print("[AutoPlace] Plant placement disabled")
end

function AutoPlace.GetStatus()
    return {
        IsRunning = AutoPlace.IsRunning,
        SeedPlacementEnabled = AutoPlace.SeedPlacementEnabled,
        PlantPlacementEnabled = AutoPlace.PlantPlacementEnabled,
        TotalSeedsPlaced = AutoPlace.TotalSeedsPlaced,
        TotalPlantsPlaced = AutoPlace.TotalPlantsPlaced
    }
end

return AutoPlace

