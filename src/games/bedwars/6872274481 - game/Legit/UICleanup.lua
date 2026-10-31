local UICleanup
local OpenInv
local KillFeed
local NoHotbar
local OldTabList
local HotbarApp = not ce and getRoactRender(require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui['hotbar-app']).HotbarApp.render) or nil
local HotbarOpenInventory = not ce and require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui['hotbar-open-inventory']).HotbarOpenInventory or nil
local old, new = {}, {}
local oldkillfeed

vape:Clean(function()
	for _, v in new do
		table.clear(v)
	end
	for _, v in old do
		table.clear(v)
	end
	table.clear(new)
	table.clear(old)
end)

local function modifyconstant(func, ind, val)
	if not func then return end
	if not old[func] then old[func] = {} end
	if not new[func] then new[func] = {} end
	if not old[func][ind] then
		local typing = type(old[func][ind])
		if typing == 'function' or typing == 'userdata' then return end
		old[func][ind] = debug.getconstant(func, ind)
	end
	if typeof(old[func][ind]) ~= typeof(val) and val ~= nil then return end

	new[func][ind] = val
	if UICleanup.Enabled then
		if val then
			debug.setconstant(func, ind, val)
		else
			debug.setconstant(func, ind, old[func][ind])
			old[func][ind] = nil
		end
	end
end

UICleanup = vape.Legit:CreateModule({
	Name = 'UI Cleanup',
	Function = function(callback)
		if ce then
			if callback then
				if OpenInv.Enabled then
					lplr.PlayerGui.hotbar['1'].ItemsHotbar['10'].Visible = false

					UICleanup:Clean(lplr.PlayerGui.ChildAdded:Connect(function(obj)
						if obj.Name == 'hotbar' then
							obj['1'].ItemsHotbar['10'].Visible = OpenInv.Enabled
						end
					end))
				end

				if NoHotbar.Enabled then
					for i,v in lplr.PlayerGui.hotbar['1'].ItemsHotbar:GetChildren() do
						if v:IsA('Frame') then
							v['1']['1'].Visible = false
						end
					end

					UICleanup:Clean(lplr.PlayerGui.ChildAdded:Connect(function(obj)
						if obj.Name == 'hotbar' then
							for i,v in obj['1'].ItemsHotbar:GetChildren() do
								if v:IsA('Frame') then
									v['1']['1'].Visible = NoHotbar.Enabled
								end
							end
						end
					end))
				end

				if KillFeed.Enabled then
					lplr.PlayerGui.KillFeedGui.Enabled = false
				end

				if OldTabList.Enabled then
					starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
				end
			else
				lplr.PlayerGui.hotbar['1'].ItemsHotbar['10'].Visible = true

				for i,v in lplr.PlayerGui.hotbar['1'].ItemsHotbar:GetChildren() do
					if v:IsA('Frame') then
						v['1']['1'].Visible = true
					end
				end

				lplr.PlayerGui.KillFeedGui.Enabled = true
				starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			end

			return
		end

		for i, v in (callback and new or old) do
			for i2, v2 in v do
				debug.setconstant(i, i2, v2)
			end
		end

		if callback then
			if OpenInv.Enabled and HotbarOpenInventory then
				oldinvrender = HotbarOpenInventory.render
				HotbarOpenInventory.render = function()
					return bedwars.Roact.createElement('TextButton', {Visible = false}, {})
				end
			end

			if KillFeed.Enabled then
				oldkillfeed = bedwars.KillFeedController.addToKillFeed
				bedwars.KillFeedController.addToKillFeed = function() end
			end

			if NoHotbar.Enabled then
				for i,v in lplr.PlayerGui.hotbar['1'].ItemsHotbar:GetChildren() do
					if v:IsA('Frame') then
						v['1']['1'].Visible = false
					end
				end

				UICleanup:Clean(lplr.PlayerGui.ChildAdded:Connect(function(obj)
					if obj.Name == 'hotbar' then
						for i,v in obj['1'].ItemsHotbar:GetChildren() do
							if v:IsA('Frame') then
								v['1']['1'].Visible = NoHotbar.Enabled
							end
						end
					end
				end))
			end

			if OldTabList.Enabled then
				starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
			end
		else
			if oldinvrender and HotbarOpenInventory then
				HotbarOpenInventory.render = oldinvrender
				oldinvrender = nil
			end

			if KillFeed.Enabled then
				bedwars.KillFeedController.addToKillFeed = oldkillfeed
				oldkillfeed = nil
			end

			if OldTabList.Enabled then
				starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			end
		end
	end,
	Tooltip = 'Cleans up the UI for kits & main'
})
if not ce then
	UICleanup:CreateToggle({
		Name = 'Resize Health',
		Function = function(callback)
			modifyconstant(HotbarApp, 63, callback and 1 or nil)
			modifyconstant(debug.getupvalue(HotbarApp, 15).render, 31, callback and 1 or nil)
			modifyconstant(debug.getupvalue(HotbarApp, 23).tweenPosition, 16, callback and 0 or nil)
		end,
		Default = true
	})
end
NoHotbar = UICleanup:CreateToggle({
	Name = 'No Hotbar Numbers',
	Function = function(callback)
		if UICleanup.Enabled then
			for i,v in lplr.PlayerGui.hotbar['1'].ItemsHotbar:GetChildren() do
				if v:IsA('Frame') then
					v['1']['1'].Visible = not callback
				end
			end
		end
	end,
	Default = true
})
OpenInv = UICleanup:CreateToggle({
	Name = 'No Inventory Button',
	Function = function(callback)
		if ce then
			if UICleanup.Enabled then
				lplr.PlayerGui.hotbar['1'].ItemsHotbar['10'].Visible = not callback
			end
			
			return
		end

		if UICleanup.Enabled and HotbarOpenInventory then
			if callback then
				oldinvrender = HotbarOpenInventory.render
				HotbarOpenInventory.render = function()
					return bedwars.Roact.createElement('TextButton', {Visible = false}, {})
				end
			else
				HotbarOpenInventory.render = oldinvrender
				oldinvrender = nil
			end
		end
	end,
	Default = true
})
KillFeed = UICleanup:CreateToggle({
	Name = 'No Kill Feed',
	Function = function(callback)
		if UICleanup.Enabled then
			if ce then
				lplr.PlayerGui.KillFeedGui.Enabled = not callback
				return
			end

			if callback then
				oldkillfeed = bedwars.KillFeedController.addToKillFeed
				bedwars.KillFeedController.addToKillFeed = function() end
			else
				bedwars.KillFeedController.addToKillFeed = oldkillfeed
				oldkillfeed = nil
			end
		end
	end,
	Default = true
})
OldTabList = UICleanup:CreateToggle({
	Name = 'Old Player List',
	Function = function(callback)
		if UICleanup.Enabled then
			starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, callback)
		end
	end,
	Default = true
})
if not ce then
	UICleanup:CreateToggle({
		Name = 'Fix Queue Card',
		Function = function(callback)
			modifyconstant(bedwars.QueueCard.render, 15, callback and 0.1 or nil)
		end,
		Default = true
	})
end