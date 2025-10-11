--[[
    🎯 Plant Vs Brainrot - Auto Turn In Module
    Automatically turn in wanted brainrots for prison rewards
    
    Features:
    - Monitor wanted brainrot name
    - Check if player owns it
    - Auto turn in when conditions met
]]

local AutoTurnIn = {
    Version = "1.0.0",
    
    -- State
    IsRunning = false,
    TotalTurnIns = 0,
    CurrentWanted = nil,
    
    -- Settings
    Settings = {
        AutoTurnInEnabled = false,
        CheckInterval = 2, -- Check every 2 seconds
    },
    
    -- Dependencies
    Services = nil,
    References = nil,
    Brain = nil,
    
    -- Cached Data
    TurnInRemote = nil,
    EventTrackModule = nil,
    PlayerDataModule = nil,
    BrainrotRegistry = nil,
}

--[[
    ========================================
    Initialization
    ========================================
]]

function AutoTurnIn.Init(services, references, brain)
    AutoTurnIn.Services = services
    AutoTurnIn.References = references
    AutoTurnIn.Brain = brain
    
    -- Cache remote and modules
    pcall(function()
        AutoTurnIn.TurnInRemote = AutoTurnIn.Services.ReplicatedStorage
            :WaitForChild("Remotes", 5)
            :WaitForChild("Events", 5)
            :WaitForChild("Prison", 5)
            :WaitForChild("Interact", 5)
        
        -- Load modules for reading wanted info
        local modules = AutoTurnIn.Services.ReplicatedStorage:FindFirstChild("Modules")
        if modules then
            local library = modules:FindFirstChild("Library")
            if library then
                local eventTracks = library:FindFirstChild("EventTracks")
                if eventTracks then
                    local prisonTrack = eventTracks:FindFirstChild("Prison")
                    if prisonTrack then
                        AutoTurnIn.EventTrackModule = require(prisonTrack)
                    end
                end
            end
            
            -- Load PlayerData module
            local playerData = modules:FindFirstChild("PlayerData")
            if playerData then
                AutoTurnIn.PlayerDataModule = require(playerData)
            end
            
            -- Load Brainrot Registry
            local registries = modules:FindFirstChild("Registries")
            if registries then
                local brainrotReg = registries:FindFirstChild("BrainrotRegistry")
                if brainrotReg then
                    AutoTurnIn.BrainrotRegistry = require(brainrotReg)
                end
            end
        end
    end)
    
    return true
end

--[[
    ========================================
    Helper Functions
    ========================================
]]

-- Get current wanted brainrot name
function AutoTurnIn.GetWantedBrainrot()
    if not AutoTurnIn.PlayerDataModule or not AutoTurnIn.EventTrackModule then
        return nil
    end
    
    local success, result = pcall(function()
        local playerData = AutoTurnIn.PlayerDataModule:GetData()
        if not playerData then return nil end
        
        local claimedRewards = playerData.Data.ClaimedRewards.Prison or 0
        local nextWanted = AutoTurnIn.EventTrackModule[claimedRewards + 1]
        
        return nextWanted
    end)
    
    if success then
        return result
    else
        return nil
    end
end

-- Check if player owns the wanted brainrot
function AutoTurnIn.HasWantedBrainrot(wantedName)
    if not wantedName then return false end
    
    local character = AutoTurnIn.References.LocalPlayer.Character
    local backpack = AutoTurnIn.References.LocalPlayer:FindFirstChild("Backpack")
    
    if not character and not backpack then return false end
    
    -- Check character
    if character then
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") and child.Name == wantedName then
                return true
            end
        end
    end
    
    -- Check backpack
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") and child.Name == wantedName then
                return true
            end
        end
    end
    
    return false
end

-- Turn in the wanted brainrot
function AutoTurnIn.TurnIn()
    if not AutoTurnIn.TurnInRemote then
        return false
    end
    
    local success = pcall(function()
        AutoTurnIn.TurnInRemote:FireServer("TurnIn")
        AutoTurnIn.TotalTurnIns = AutoTurnIn.TotalTurnIns + 1
    end)
    
    return success
end

--[[
    ========================================
    Main Check Loop
    ========================================
]]

function AutoTurnIn.CheckLoop()
    task.spawn(function()
        while AutoTurnIn.IsRunning and AutoTurnIn.Settings.AutoTurnInEnabled do
            -- Get current wanted brainrot
            local wantedName = AutoTurnIn.GetWantedBrainrot()
            AutoTurnIn.CurrentWanted = wantedName
            
            if wantedName then
                -- Check if we own it
                if AutoTurnIn.HasWantedBrainrot(wantedName) then
                    -- Turn it in
                    AutoTurnIn.TurnIn()
                    
                    -- Wait a bit longer after turning in
                    task.wait(3)
                end
            end
            
            -- Wait before next check
            task.wait(AutoTurnIn.Settings.CheckInterval)
        end
    end)
end

--[[
    ========================================
    Start/Stop Functions
    ========================================
]]

function AutoTurnIn.Start()
    if AutoTurnIn.IsRunning then return false end
    
    -- Validate remote
    if not AutoTurnIn.TurnInRemote then
        warn("[AutoTurnIn] ⚠️ Failed to find turn in remote!")
        return false
    end
    
    AutoTurnIn.IsRunning = true
    AutoTurnIn.TotalTurnIns = 0
    AutoTurnIn.CheckLoop()
    
    return true
end

function AutoTurnIn.Stop()
    if not AutoTurnIn.IsRunning then return false end
    
    AutoTurnIn.IsRunning = false
    AutoTurnIn.CurrentWanted = nil
    return true
end

--[[
    ========================================
    Status Functions
    ========================================
]]

function AutoTurnIn.GetStatus()
    return {
        IsRunning = AutoTurnIn.IsRunning,
        TotalTurnIns = AutoTurnIn.TotalTurnIns,
        CurrentWanted = AutoTurnIn.CurrentWanted or "None"
    }
end

return AutoTurnIn

