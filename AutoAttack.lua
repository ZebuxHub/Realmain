--[[
    🌱 Plant Vs Brainrot - Auto Attack Module
    Automatic combat system with targeting and movement
    
    Features:
    - Auto equip weapon (Leather Grip Bat)
    - Multiple targeting modes (Random, High HP, Low HP)
    - Multiple movement modes (Walk, TP, Tween)
    - Player-based targeting with AssociatedPlayer attribute
    - Health-based targeting (Current or Max)
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
        TargetPlayerID = nil,  -- If set, only target this player's brainrots
        AttackRange = 15,  -- Distance to target before attacking
        AttackInterval = 0.5,  -- Seconds between attacks
    },
    
    -- Dependencies
    Services = nil,
    References = nil,
    Brain = nil,
    
    -- Connections
    AttackLoop = nil,
    EquippedConnection = nil
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

-- Equip weapon (Leather Grip Bat)
function AutoAttack.EquipWeapon()
    local success = pcall(function()
        local character = AutoAttack.References.LocalPlayer.Character
        local backpack = AutoAttack.References.LocalPlayer:WaitForChild("Backpack")
        
        if not character then return false end
        
        -- Find Leather Grip Bat in backpack or character
        local weapon = backpack:FindFirstChild("Leather Grip Bat") or character:FindFirstChild("Leather Grip Bat")
        
        if weapon and weapon:IsA("Tool") then
            -- Unequip other tools first
            for _, tool in ipairs(character:GetChildren()) do
                if tool:IsA("Tool") and tool ~= weapon then
                    tool.Parent = backpack
                end
            end
            
            -- Equip weapon
            if weapon.Parent ~= character then
                weapon.Parent = character
            end
            
            return true
        end
        
        return false
    end)
    
    return success
end

-- Get all available targets from workspace
function AutoAttack.GetAllTargets()
    local targets = {}
    
    pcall(function()
        local brainrots = workspace.ScriptedMap:FindFirstChild("Brainrots")
        if not brainrots then return end
        
        for _, brainrot in ipairs(brainrots:GetChildren()) do
            if brainrot:IsA("Model") then
                local id = brainrot.Name
                local associatedPlayer = brainrot:GetAttribute("AssociatedPlayer")
                local health = brainrot:GetAttribute("Health") or 0
                local maxHealth = brainrot:GetAttribute("MaxHealth") or 100
                
                -- Filter by player ID if specified
                if AutoAttack.Settings.TargetPlayerID then
                    if associatedPlayer == AutoAttack.Settings.TargetPlayerID then
                        table.insert(targets, {
                            Model = brainrot,
                            ID = id,
                            PlayerID = associatedPlayer,
                            Health = health,
                            MaxHealth = maxHealth,
                            Position = brainrot:GetPivot().Position
                        })
                    end
                else
                    -- Include all targets if no player filter
                    table.insert(targets, {
                        Model = brainrot,
                        ID = id,
                        PlayerID = associatedPlayer,
                        Health = health,
                        MaxHealth = maxHealth,
                        Position = brainrot:GetPivot().Position
                    })
                end
            end
        end
    end)
    
    return targets
end

-- Select best target based on mode
function AutoAttack.SelectTarget()
    local targets = AutoAttack.GetAllTargets()
    
    if #targets == 0 then
        return nil
    end
    
    local mode = AutoAttack.Settings.TargetMode
    local healthMode = AutoAttack.Settings.HealthMode
    
    -- Random mode
    if mode == "Random" then
        return targets[math.random(1, #targets)]
    end
    
    -- Sort by health (use Current or Max health based on setting)
    table.sort(targets, function(a, b)
        local aValue = (healthMode == "Max") and a.MaxHealth or a.Health
        local bValue = (healthMode == "Max") and b.MaxHealth or b.Health
        
        if mode == "HighHP" then
            return aValue > bValue  -- Highest first
        else  -- LowHP
            return aValue < bValue  -- Lowest first
        end
    end)
    
    return targets[1]
end

-- Move to target based on movement mode
function AutoAttack.MoveToTarget(target)
    if not target or not target.Position then return false end
    
    local character = AutoAttack.References.LocalPlayer.Character
    if not character then return false end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return false end
    
    local targetPosition = target.Position
    local distance = (humanoidRootPart.Position - targetPosition).Magnitude
    
    -- Already in range
    if distance <= AutoAttack.Settings.AttackRange then
        return true
    end
    
    local movementMode = AutoAttack.Settings.MovementMode
    
    if movementMode == "TP" then
        -- Instant teleport
        pcall(function()
            humanoidRootPart.CFrame = CFrame.new(targetPosition + Vector3.new(0, 3, 0))
        end)
        return true
        
    elseif movementMode == "Tween" then
        -- Smooth tween
        local TweenService = game:GetService("TweenService")
        local tweenInfo = TweenInfo.new(
            distance / 50,  -- Duration based on distance
            Enum.EasingStyle.Linear,
            Enum.EasingDirection.InOut
        )
        
        local tween = TweenService:Create(
            humanoidRootPart,
            tweenInfo,
            {CFrame = CFrame.new(targetPosition + Vector3.new(0, 3, 0))}
        )
        
        tween:Play()
        tween.Completed:Wait()
        return true
        
    elseif movementMode == "Walk" then
        -- Use Humanoid to walk
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:MoveTo(targetPosition)
            
            -- Wait until close enough or timeout
            local timeout = 10  -- 10 seconds max
            local startTime = tick()
            
            while (humanoidRootPart.Position - targetPosition).Magnitude > AutoAttack.Settings.AttackRange do
                if tick() - startTime > timeout then
                    return false
                end
                task.wait(0.1)
            end
            
            return true
        end
    end
    
    return false
end

-- Attack target
function AutoAttack.AttackTarget(target)
    if not target or not target.ID then return false end
    
    local success = pcall(function()
        local args = {
            [1] = {
                [1] = target.ID
            }
        }
        
        AutoAttack.Services.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AttacksServer"):WaitForChild("WeaponAttack"):FireServer(unpack(args))
    end)
    
    if success then
        AutoAttack.TotalAttacks = AutoAttack.TotalAttacks + 1
    end
    
    return success
end

-- Check if target is still valid
function AutoAttack.IsTargetValid(target)
    if not target or not target.Model then return false end
    
    -- Check if model still exists
    if not target.Model.Parent then return false end
    
    -- Check if health > 0
    local currentHealth = target.Model:GetAttribute("Health") or 0
    if currentHealth <= 0 then return false end
    
    return true
end

--[[
    ========================================
    Main Attack Loop
    ========================================
]]

function AutoAttack.AttackLoop()
    task.spawn(function()
        while AutoAttack.IsRunning and AutoAttack.Settings.AutoAttackEnabled do
            -- Ensure weapon is equipped
            AutoAttack.EquipWeapon()
            
            -- Select target
            local target = AutoAttack.SelectTarget()
            
            if target then
                AutoAttack.CurrentTarget = target
                
                -- Move to target
                local inRange = AutoAttack.MoveToTarget(target)
                
                if inRange then
                    -- Attack target
                    AutoAttack.AttackTarget(target)
                end
                
                -- Wait between attacks
                task.wait(AutoAttack.Settings.AttackInterval)
                
                -- Check if target is still valid
                if not AutoAttack.IsTargetValid(target) then
                    AutoAttack.CurrentTarget = nil
                end
            else
                -- No targets, wait and retry
                AutoAttack.CurrentTarget = nil
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
    if AutoAttack.IsRunning then
        return false
    end
    
    AutoAttack.IsRunning = true
    AutoAttack.TotalAttacks = 0
    
    -- Equip weapon immediately
    AutoAttack.EquipWeapon()
    
    -- Start attack loop
    AutoAttack.AttackLoop()
    
    -- Monitor weapon unequip (re-equip if needed)
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

