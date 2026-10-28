local Sprint
local old

local function watchSpeed(humanoid) -- im going to fucking kill you mimo for writing such bad code
	Sprint:Clean(humanoid:GetPropertyChangedSignal('WalkSpeed'):Connect(function()
		if not Sprint.Enabled then return end

		if bedwars.SprintController.isSprinting then
			bedwars.SprintController.sprinting = bedwars.SprintController.isSprinting
		end

		if not bedwars.SprintController.sprinting or (bedwars.SprintController.moveSpeedMultiplier or 1) <= 0 then return end
		bedwars.SprintController:setSpeed(bedwars.SprintController.RUN_SPEED or 20)
	end))
end

Sprint = vape.Categories.Combat:CreateModule({
	Name = 'Sprint',
	Function = function(callback)
		if inputService.TouchEnabled then 
			pcall(function() 
				lplr.PlayerGui.MobileUI['4'].Visible = not callback 
			end) 
		end

		if callback then
			old = bedwars.SprintController.stopSprinting
			bedwars.SprintController.stopSprinting = function(...)
				local call = old(...)
				bedwars.SprintController:startSprinting()
				return call
			end
			Sprint:Clean(entitylib.Events.LocalAdded:Connect(function() 
				task.delay(0.1, function() 
					bedwars.SprintController:stopSprinting() 
				end) 
			end))

			if ce then
				contextActionService:BindActionAtPriority('VapeSprint', function(_, inputState)
					if inputState == Enum.UserInputState.Begin then
						bedwars.SprintController:startSprinting()
					end
					return Enum.ContextActionResult.Pass
				end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftShift, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D)

				if entitylib.isAlive then
					watchSpeed(entitylib.character.Humanoid)
				end

				Sprint:Clean(entitylib.Events.LocalAdded:Connect(function()
					if entitylib.isAlive then
						watchSpeed(entitylib.character.Humanoid)
					end
				end))
			end

			bedwars.SprintController:stopSprinting()
		else
			if ce then
				contextActionService:UnbindAction('VapeSprint')
			end
			bedwars.SprintController.stopSprinting = old
			bedwars.SprintController:stopSprinting()
		end
	end,
	Tooltip = 'Sets your sprinting to true.'
})