--[[
    🌱 Plant Vs Brainrot - Auto Attack Module
    Automatic combat system with targeting and movement
    
    Features:
    - Auto equip weapon (Leather Grip Bat)
    - Multiple targeting modes (Random, High HP, Low HP)
    - Multiple movement modes (Walk, TP, Tween)
    - ONLY attacks brainrots in YOUR plot with YOUR UserID
    - Health-based targeting (Current or Max)
    
    Security:
    - Scans: workspace.ScriptedMap.Brainrots (global location)
    - Plot filter: brainrot:GetAttribute("Plot") == YourPlot
    - Only attacks brainrots in YOUR plot (AssociatedPlayer not used by game)
]]

local AutoAttack = {
    Version = "1.0.0",
    
    -- State
    IsRunning = false,
    TotalAttacks = 0,
    CurrentTarget = nil,
    
    -- Settings
    Settings = {
        AutoAttackEnabled = false,
        TargetMode = "Random",  -- "Random", "HighHP", "LowHP"
        MovementMode = "TP",  -- "TP", "Tween", "Walk"
        HealthMode = "Current",  -- "Current", "Max"
        AttackInterval = 0.5,  -- Seconds between attacks
    },
    
    -- Dependencies
    Services = nil,
    References = nil,
    Brain = nil,
    
    -- Connections & Cached Remotes
    AttackLoop = nil,
    EquippedConnection = nil,
    HealthMonitorConnection = nil,
    AttackRemote = nil  -- Cached for performance
}

--[[
    ========================================
    Initialization
    ========================================
]]

function AutoAttack.Init(services, references, brain)
    AutoAttack.Services = services
    AutoAttack.References = references
    AutoAttack.Brain = brain
    
    return true
end

--[[
    ========================================
    Helper Functions
    ========================================
]]

-- Format numbers
local function FormatNumber(num)
    if num >= 1000000000 then
        return string.format("%.1fB", num / 1000000000)
    elseif num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    else
        return tostring(math.floor(num))
    end
end

-- Equip weapon (Leather Grip Bat) - Optimized
function AutoAttack.EquipWeapon()
    local success, result = pcall(function()
        local character = AutoAttack.References.LocalPlayer.Character
        if not character then return false end
        
        local backpack = AutoAttack.References.LocalPlayer:FindFirstChild("Backpack")
        if not backpack then return false end
        
        -- Check if already equipped (fast path)
        local weapon = character:FindFirstChild("Leather Grip Bat")
        if weapon then return true end
        
        -- Find in backpack
        weapon = backpack:FindFirstChild("Leather Grip Bat")
        if weapon and weapon:IsA("Tool") then
            weapon.Parent = character
            return true
        end
        
        return false
    end)
    
    return success and result
end

-- Get player's owned plot number
function AutoAttack.GetPlayerPlot()
    local success, plotNum = pcall(function()
        return AutoAttack.References.LocalPlayer:GetAttribute("Plot")
    end)
    
    if success and plotNum then
        return tostring(plotNum)
    end
    
    return nil
end

-- Get all available targets - Optimized for performance
function AutoAttack.GetAllTargets()
    local targets = {}
    local playerPlot = AutoAttack.GetPlayerPlot()
    if not playerPlot then return targets end
    
    local success = pcall(function()
        local scriptedMap = workspace:FindFirstChild("ScriptedMap")
        if not scriptedMap then return end
        
        local brainrots = scriptedMap:FindFirstChild("Brainrots")
        if not brainrots then return end
        
        local playerPlotStr = tostring(playerPlot)
        
        -- Optimized: Single pass, minimal allocations
        for _, brainrot in ipairs(brainrots:GetChildren()) do
            if brainrot:IsA("Model") then
                local health = brainrot:GetAttribute("Health")
                
                -- Fast rejection: Skip dead brainrots immediately
                if health and health > 0 then
                    local plot = brainrot:GetAttribute("Plot")
                    
                    -- Only process if plot matches
                    if tostring(plot) == playerPlotStr then
                        targets[#targets + 1] = {
                            Model = brainrot,
                            ID = brainrot.Name,
                            Health = health,
                            MaxHealth = brainrot:GetAttribute("MaxHealth") or 100
                        }
                    end
                end
            end
        end
    end)
    
    return targets
end

-- Select best target - Optimized
function AutoAttack.SelectTarget()
    local targets = AutoAttack.GetAllTargets()
    if #targets == 0 then return nil end
    
    local mode = AutoAttack.Settings.TargetMode
    
    -- Random mode (fastest)
    if mode == "Random" then
        return targets[math.random(1, #targets)]
    end
    
    -- Health-based selection (optimized: single pass for min/max)
    local healthMode = AutoAttack.Settings.HealthMode
    local bestTarget = targets[1]
    local bestValue = (healthMode == "Max") and bestTarget.MaxHealth or bestTarget.Health
    
    for i = 2, #targets do
        local target = targets[i]
        local value = (healthMode == "Max") and target.MaxHealth or target.Health
        
        if mode == "HighHP" then
            if value > bestValue then
                bestTarget = target
                bestValue = value
            end
        else  -- LowHP
            if value < bestValue then
                bestTarget = target
                bestValue = value
            end
        end
    end
    
    return bestTarget
end

-- Move to target - Optimized
function AutoAttack.MoveToTarget(target)
    if not target or not target.Model then return math.huge end
    
    local character = AutoAttack.References.LocalPlayer.Character
    if not character then return math.huge end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return math.huge end
    
    local targetPos = target.Model:GetPivot().Position
    local distance = (hrp.Position - targetPos).Magnitude
    
    -- Already in range
    if distance <= 5 then return distance end
    
    -- Move based on mode
    local mode = AutoAttack.Settings.MovementMode
    
    if mode == "TP" then
        pcall(function()
            local dir = (targetPos - hrp.Position).Unit
            hrp.CFrame = CFrame.new(targetPos - dir * 3)
        end)
    elseif mode == "Tween" then
        local TweenService = game:GetService("TweenService")
        local dir = (targetPos - hrp.Position).Unit
        local tween = TweenService:Create(hrp, TweenInfo.new(0.3, Enum.EasingStyle.Linear), {CFrame = CFrame.new(targetPos - dir * 3)})
        tween:Play()
    elseif mode == "Walk" then
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then humanoid:MoveTo(targetPos) end
    end
    
    return (hrp.Position - targetPos).Magnitude
end

-- Attack target - Optimized with remote caching
function AutoAttack.AttackTarget(target)
    if not target or not target.ID then return false end
    
    local success, err = pcall(function()
        -- Cache remote for performance
        if not AutoAttack.AttackRemote then
            AutoAttack.AttackRemote = AutoAttack.Services.ReplicatedStorage
                :WaitForChild("Remotes", 5)
                :WaitForChild("AttacksServer", 5)
                :WaitForChild("WeaponAttack", 5)
        end
        
        if AutoAttack.AttackRemote then
            -- Fire with correct format: {{target_id}}
            local args = {
                [1] = {
                    [1] = target.ID
                }
            }
            AutoAttack.AttackRemote:FireServer(unpack(args))
            AutoAttack.TotalAttacks = AutoAttack.TotalAttacks + 1
            return true
        else
            warn("[AutoAttack] ⚠️ WeaponAttack remote not found!")
            return false
        end
    end)
    
    if not success then
        warn("[AutoAttack] ❌ Attack error:", err)
        -- Reset cached remote in case path changed
        AutoAttack.AttackRemote = nil
    end
    
    return success
end

-- Check if target is valid - Optimized
function AutoAttack.IsTargetValid(target)
    if not target or not target.Model then return false end
    if not target.Model.Parent then return false end
    
    local health = target.Model:GetAttribute("Health")
    return health and health > 0
end

-- Monitor target health - Optimized
function AutoAttack.MonitorTargetHealth(target)
    if AutoAttack.HealthMonitorConnection then
        AutoAttack.HealthMonitorConnection:Disconnect()
    end
    
    if not target or not target.Model then return end
    
    AutoAttack.HealthMonitorConnection = target.Model:GetAttributeChangedSignal("Health"):Connect(function()
        if (target.Model:GetAttribute("Health") or 0) <= 0 then
            AutoAttack.CurrentTarget = nil
            if AutoAttack.HealthMonitorConnection then
                AutoAttack.HealthMonitorConnection:Disconnect()
                AutoAttack.HealthMonitorConnection = nil
            end
        end
    end)
end

--[[
    ========================================
    Main Attack Loop
    ========================================
]]

-- Main attack loop - Highly optimized
function AutoAttack.AttackLoop()
    task.spawn(function()
        while AutoAttack.IsRunning and AutoAttack.Settings.AutoAttackEnabled do
            -- Equip weapon (fast path if already equipped)
            AutoAttack.EquipWeapon()
            
            -- Get or refresh target
            if not AutoAttack.IsTargetValid(AutoAttack.CurrentTarget) then
                local newTarget = AutoAttack.SelectTarget()
                AutoAttack.CurrentTarget = newTarget
                if newTarget then
                    AutoAttack.MonitorTargetHealth(newTarget)
                end
            end
            
            local target = AutoAttack.CurrentTarget
            
            if target then
                -- Validate before action
                if not AutoAttack.IsTargetValid(target) then
                    AutoAttack.CurrentTarget = nil
                    continue
                end
                
                -- Move and attack
                local distance = AutoAttack.MoveToTarget(target)
                
                if AutoAttack.IsTargetValid(target) and distance <= 5 then
                    AutoAttack.AttackTarget(target)
                    task.wait(AutoAttack.Settings.AttackInterval)
                else
                    task.wait(0.1)
                end
            else
                -- No targets, check less frequently
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

function AutoAttack.Start()
    if AutoAttack.IsRunning then return false end
    
    AutoAttack.IsRunning = true
    AutoAttack.TotalAttacks = 0
    
    AutoAttack.EquipWeapon()
    AutoAttack.AttackLoop()
    
    local character = AutoAttack.References.LocalPlayer.Character
    if character then
        AutoAttack.EquippedConnection = character.ChildRemoved:Connect(function(child)
            if child.Name == "Leather Grip Bat" and AutoAttack.IsRunning then
                task.wait(0.1)
                AutoAttack.EquipWeapon()
            end
        end)
    end
    
    return true
end

function AutoAttack.Stop()
    if not AutoAttack.IsRunning then
        return false
    end
    
    AutoAttack.IsRunning = false
    AutoAttack.CurrentTarget = nil
    
    -- Disconnect weapon monitor
    if AutoAttack.EquippedConnection then
        AutoAttack.EquippedConnection:Disconnect()
        AutoAttack.EquippedConnection = nil
    end
    
    -- Disconnect health monitor
    if AutoAttack.HealthMonitorConnection then
        AutoAttack.HealthMonitorConnection:Disconnect()
        AutoAttack.HealthMonitorConnection = nil
    end
    
    return true
end

--[[
    ========================================
    Status Functions
    ========================================
]]

function AutoAttack.GetStatus()
    return {
        IsRunning = AutoAttack.IsRunning,
        TotalAttacks = AutoAttack.TotalAttacks,
        CurrentTarget = AutoAttack.CurrentTarget,
        Settings = AutoAttack.Settings
    }
end

--[[
    ========================================
    Return Module
    ========================================
]]

return AutoAttack

