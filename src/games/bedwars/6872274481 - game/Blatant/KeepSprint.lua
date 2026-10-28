-- debug.setconstant needs a debug enabled executor, hiding it on emulated ones
if ce then return end

vape.Categories.Blatant:CreateModule({
	Name = 'KeepSprint',
	Function = function(callback)
		if ce then return end
		debug.setconstant(bedwars.SprintController.startSprinting, 5, callback and 'blockSprinting' or 'blockSprint')
		bedwars.SprintController:stopSprinting()
	end,
	Tooltip = 'Lets you sprint with a speed potion.'
})