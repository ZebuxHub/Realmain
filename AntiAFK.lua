-- AntiAFK.lua - Anti-AFK System
-- Removes game's AFK detection and prevents kicks

local AntiAFK = {}

-- Services
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")

-- State
local isEnabled = false
local connection = nil
local LocalPlayer = Players.LocalPlayer

-- Initialize and remove game's AFK script
function AntiAFK.Init()
    -- Remove the game's AFK detection script
    pcall(function()
        local playerScripts = LocalPlayer:WaitForChild("PlayerScripts", 5)
        if playerScripts then
            local other = playerScripts:FindFirstChild("Other")
            if other then
                local afkScript = other:FindFirstChild("AFK")
                if afkScript then
                    afkScript:Destroy()
                end
            end
        end
    end)
    
    -- Auto-enable
    AntiAFK.Enable()
    
    return true
end

-- Enable Anti-AFK
function AntiAFK.Enable()
    if isEnabled then return end
    
    isEnabled = true
    
    -- Prevent idle kick
    connection = LocalPlayer.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
end

-- Disable Anti-AFK
function AntiAFK.Disable()
    if not isEnabled then return end
    
    isEnabled = false
    
    if connection then
        connection:Disconnect()
        connection = nil
    end
end

-- Get status
function AntiAFK.IsEnabled()
    return isEnabled
end

return AntiAFK

