local NoFall

NoFall = vape.Categories.Blatant:CreateModule({
	Name = 'NoFall',
	Function = function(callback)
		if callback then
			NoFall:Clean(runService.PostSimulation:Connect(function(dt)
				if entitylib.isAlive then
					local root, oldVelo = entitylib.character.RootPart
					oldVelo = root.AssemblyLinearVelocity.Y
					if root.AssemblyLinearVelocity.Y < -45 then
						root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 44, root.AssemblyLinearVelocity.Z)
						entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Landed)

						runService.PreSimulation:Wait()
						root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, oldVelo, root.AssemblyLinearVelocity.Z)
					end
				end
			end))
		end
	end,
	Tooltip = 'Prevents taking fall damage.'
})