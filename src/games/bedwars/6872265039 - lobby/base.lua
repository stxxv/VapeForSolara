local cloneref = cloneref or function(obj)
	return obj
end

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local inputService = cloneref(game:GetService('UserInputService'))

local lplr = playersService.LocalPlayer
local vape = shared.vape
local entitylib = vape.Libraries.entity
local sessioninfo = vape.Libraries.sessioninfo
getgenv().bedwars = {}

local function notif(...)
	return vape:CreateNotification(...)
end

local function run(func)
	xpcall(func, function(err)
        local time, timestamp, date, filecontents, contents = string.lower(os.date('%I:%M%p')), nil, os.date('%d/%m/%y')

        do
            if isfile('newvape/error.txt') then
                filecontents = readfile('newvape/error.txt')
            end

            timestamp = `{time}, {date}`
            contents = ((filecontents and filecontents ~= '') and `{filecontents}\n\ntimestamp: {timestamp}\nerror: {debug.traceback(err, 2)}`) or `timestamp: {timestamp}\nerror: {debug.traceback(err, 2)}`
        end

        writefile('newvape/error.txt', contents)
        notif('Vape', `Module failed to load: {tostring(err)}`, 10, 'alert')
    end)
end

local function downloadFile(path, callback)
	if not isfile(path) then
		local success, data = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/stxxv/VapeCompiled/'..readfile('newvape/profiles/commit.txt')..'/'..select(1, path:gsub('newvape/', '')), true)
		end)
		if not success or data == '404: Not Found' then
			error(data)
		end
		if path:find('.lua') then
			data = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..data
		end
		writefile(path, data)
	end
	return (callback or readfile)(path)
end
getgenv().downloadFile = downloadFile

run(function()
	for _, v in {'newvape/libraries/bedwars', 'newvape/libraries/bedwars/lobby'} do
		if not isfolder(v) then
			makefolder(v)
		end
	end

	local construct = loadstring(downloadFile('newvape/libraries/bedwars/lobby/construct.lua'))()
	repeat task.wait() until construct ~= nil and construct.loaded
end)

entitylib.start()

for i, v in vape.Modules do
	if v.Category == 'Combat' then
		vape:Remove(i)
	end
end
