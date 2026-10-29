local Velocity
local Horizontal
local Vertical
local Chance
local TargetCheck
local rand, old, constants = Random.new()

Velocity = vape.Categories.Combat:CreateModule({
	Name = 'Velocity',
	Function = function(callback)
		if callback then
			if not ce then
				old = bedwars.KnockbackUtil.applyKnockback
				bedwars.KnockbackUtil.applyKnockback = function(root, mass, dir, knockback, ...)
					if rand:NextNumber(0, 100) > Chance.Value then return end
					local check = (not TargetCheck.Enabled) or entitylib.EntityPosition({
						Range = 50,
						Part = 'RootPart',
						Players = true
					})

					if check then
						knockback = knockback or {}
						if Horizontal.Value == 0 and Vertical.Value == 0 then return end
						knockback.horizontal = (knockback.horizontal or 1) * (Horizontal.Value / 100)
						knockback.vertical = (knockback.vertical or 1) * (Vertical.Value / 100)
					end
					
					return old(root, mass, dir, knockback, ...)
				end
			else
				constants = constants or {
					horizontal = replicatedStorage.TS.damage['knockback-util']:GetAttribute('ConstantManager_kbDirectionStrength'),
					vertical = replicatedStorage.TS.damage['knockback-util']:GetAttribute('ConstantManager_kbUpwardStrength')
				}
				
				local check = (not TargetCheck.Enabled) or entitylib.EntityPosition({
					Range = 50,
					Part = 'RootPart',
					Players = true
				})

				replicatedStorage.TS.damage['knockback-util']:SetAttribute('ConstantManager_kbDirectionStrength', (check and constants.horizontal) or constants.horizontal * (Horizontal.Value / 100))
				replicatedStorage.TS.damage['knockback-util']:SetAttribute('ConstantManager_kbUpwardStrength', (check and constants.vertical) or constants.vertical * (Vertical.Value / 100))
			end
		else
			if not ce then
				bedwars.KnockbackUtil.applyKnockback = old
			else
				replicatedStorage.TS.damage['knockback-util']:SetAttribute('ConstantManager_kbDirectionStrength', constants.horizontal)
				replicatedStorage.TS.damage['knockback-util']:SetAttribute('ConstantManager_kbUpwardStrength', constants.vertical)
			end
		end
	end,
	Tooltip = 'Reduces knockback taken'
})
Horizontal = Velocity:CreateSlider({
	Name = 'Horizontal',
	Min = 0,
	Max = 100,
	Default = 0,
	Suffix = '%',
	Function = function(value)
		if not Velocity.Enabled then return end
		replicatedStorage.TS.damage['knockback-util']:SetAttribute('ConstantManager_kbDirectionStrength', constants.horizontal * (value / 100))
	end
})
Vertical = Velocity:CreateSlider({
	Name = 'Vertical',
	Min = 0,
	Max = 100,
	Default = 0,
	Suffix = '%',
	Function = function(value)
		if not Velocity.Enabled then return end
		replicatedStorage.TS.damage['knockback-util']:SetAttribute('ConstantManager_kbUpwardStrength', constants.vertical * (value / 100))
	end
})

if not ce then
	Chance = Velocity:CreateSlider({
		Name = 'Chance',
		Min = 0,
		Max = 100,
		Default = 100,
		Suffix = '%'
	})
end
TargetCheck = Velocity:CreateToggle({Name = 'Only when targeting'})