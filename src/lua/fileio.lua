-- © 2008 David Given.
-- WordGrinder is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local ITALIC = wg.ITALIC
local UNDERLINE = wg.UNDERLINE
local ParseWord = wg.parseword
local bitand = bit32.band
local bitor = bit32.bor
local bitxor = bit32.bxor
local bit = bit32.btest

local MAGIC = "WordGrinder dumpfile v1: this is not a text file!"

local function writetostream(object, fp)
	local type_lookup = {
		[DocumentSetClass] = "DS",
		[DocumentClass] = "D",
		[ParagraphClass] = "P",
		[WordClass] = "W",
		[MenuClass] = "M",
	}
	
	local cache = {}
	local cacheid = 1
	local function save(t)
		if cache[t] then
			fp:write(cache[t], "\n")
			return
		end
		cache[t] = cacheid
		cacheid = cacheid + 1
		
		if (type(t) == "table") then
			local m = getmetatable(t)
			if m then
				m = type_lookup[m.__index]
			else
				m = "T"
			end
			fp:write(m, "\n", #t, "\n")
			
			for _, i in ipairs(t) do
				save(i)
			end
			for k, v in pairs(t) do
				if (type(k) ~= "number") then
					save(k)
					save(v)
				end
			end
			fp:write(".\n")
		elseif (type(t) == "boolean") then
			if t then
				fp:write("B\nT\n")
			else
				fp:write("B\nF\n")
			end
		elseif (type(t) == "string") then
			fp:write("S\n", t, "\n")
		elseif (type(t) == "number") then
			fp:write("N\n", t, "\n")
		else
			error("unsupported type "..type(t))
		end
	end
	
	save(object)
	
	return true
end

function SaveDocumentSetRaw(filename)
	local fp, e = io.open(filename, "wb")
	if not fp then
		return false, e
	end
	
	DocumentSet:purge()
	fp:write(MAGIC, "\n")
	local r = writetostream(DocumentSet, fp)
	fp:close()
	
	return r
end

function Cmd.SaveCurrentDocumentAs(filename)
	if not filename then
		filename = FileBrowser("Save Document Set", "Save as:", true)
		if not filename then
			return false
		end
		DocumentSet.name = filename
	end

	ImmediateMessage("Saving...")
	DocumentSet:clean()	
	local r, e = SaveDocumentSetRaw(DocumentSet.name)
	if not r then
		ModalMessage("Save failed", "The document could not be saved: "..e)
	else
		NonmodalMessage("Save succeeded.")
	end
	return r	
end

function Cmd.SaveCurrentDocument()
	local name = DocumentSet.name
	if not name then
		name = FileBrowser("Save Document Set", "Save as:", true)
		if not name then
			return false
		end
		DocumentSet.name = name
	end
	
	return Cmd.SaveCurrentDocumentAs(name)
end

local function loadfromstream(fp)
	local cache = {}
	local load
	
	local function populate_table(t)
		local n = tonumber(fp:read("*l"))
		for i = 1, n do
			t[i] = load()
		end
		
		while true do
			local k = load()
			if not k then
				break
			end
			
			t[k] = load()
		end
		
		return t
	end
	
	local load_cb = {
		["DS"] = function()
			local t = {}
			setmetatable(t, {__index = DocumentSetClass})
			cache[#cache + 1] = t
			return populate_table(t)
		end,
		
		["D"] = function()
			local t = {}
			setmetatable(t, {__index = DocumentClass})
			cache[#cache + 1] = t
			return populate_table(t)
		end,
		
		["P"] = function()
			local t = {}
			setmetatable(t, {__index = ParagraphClass})
			cache[#cache + 1] = t
			return populate_table(t)
		end,
		
		["W"] = function()
			local t = {}
			setmetatable(t, {__index = WordClass})
			cache[#cache + 1] = t
			return populate_table(t)
		end,
		
		["M"] = function()
			local t = {}
			setmetatable(t, {__index = MenuClass})
			cache[#cache + 1] = t
			return populate_table(t)
		end,
		
		["T"] = function()
			local t = {}
			cache[#cache + 1] = t
			return populate_table(t)
		end,
		
		["S"] = function()
			local s = fp:read("*l")
			cache[#cache + 1] = s
			return s
		end,
		
		["N"] = function()
			local n = tonumber(fp:read("*l"))
			cache[#cache + 1] = n
			return n
		end,
		
		["B"] = function()
			local s = fp:read("*l")
			s = (s == "T")
			cache[#cache + 1] = s
			return s
		end,
		
		["."] = function()
			return nil
		end
	}
	
	load = function()
		local s = fp:read("*l")
		if not s then
			error("unexpected EOF when reading file")
		end
		
		local n = tonumber(s)
		if n then
			return cache[n]
		end
		
		local f = load_cb[s]
		if not f then
			error("can't load type "..s)
		end
		return f()
	end
	
	return load()		
end

local function loaddocument(filename)
	local fp, e = io.open(filename, "rb")
	if not fp then
		return nil, ("'"..filename.."' could not be opened: "..e)
	end
	if (fp:read("*l") ~= MAGIC) then
		fp:close()
		return nil, ("'"..filename.."' is not a valid WordGrinder file.")
	end
	
	local d, e = loadfromstream(fp)
	fp:close()
	
	if not d then
		return nil, e
	end
	
	-- This should not be necessary, but we do it anyway just to be sure.
	
	d:purge()
	
	-- Even if the changed flag was set in the document on disk, remove it.
	
	d:clean()
	
	d.name = filename
	return d
end

function Cmd.LoadDocumentSet(filename)
	if not ConfirmDocumentErasure() then
		return false
	end
	
	if not filename then
		filename = FileBrowser("Load Document Set", "Load file:", false)
		if not filename then
			return false
		end
	end
	
	ImmediateMessage("Loading...")
	local d, e = loaddocument(filename)
	if not d then
		if not e then
			e = "The load failed, probably because the file could not be opened."
		end
		ModalMessage(nil, e)
		QueueRedraw()
		return false
	end
		
	DocumentSet = d
	Document = d.current
	
	ResizeScreen()
	FireEvent(Event.DocumentLoaded)
	
	RebuildParagraphStylesMenu(DocumentSet.styles)
	RebuildDocumentsMenu(DocumentSet.documents)
	QueueRedraw()
	return true
end

-----------------------------------------------------------------------------
-- Cause the document to get upgraded, if necessary.

do
	local function cb(event, token)	
		local fileformat = DocumentSet.fileformat or 1
		
		if (fileformat ~= FILEFORMAT) then
			ModalMessage("Upgrading document",
				"You are trying to open a file belonging to an earlier "..
				"version of WordGrinder. That's not a problem, but if you "..
				"save the file again it may not work on the old version. "..
				"Also, all keybindings defined in this file will get reset "..
				"to their default values.")
			
			ImmediateMessage("Upgrading...")
			FireEvent(Event.DocumentUpgrade, fileformat, FILEFORMAT)
				
			DocumentSet.fileformat = FILEFORMAT
			DocumentSet.menu = CreateMenu()
			DocumentSet:touch()
		end
		
		-- This happens here because it must happen before the result of the
		-- DocumentLoaded handlers fire, but after the DocumentUpgrade
		-- handlers. It's not really a very elegant place for it.
		
		FireEvent(Event.RegisterAddons)
	end
	
	AddEventListener(Event.DocumentLoaded, cb)
end

-----------------------------------------------------------------------------
-- Upgrade the document, if necessary.

do
	local function cb(event, token, oldversion, newversion)
		-- Upgrade version 1 to 2.
		
		if (oldversion < 2) then
			-- Update wordcount.

			for _, document in ipairs(DocumentSet) do
				local wc = 0
				
				for _, p in ipairs(document) do
					wc = wc + #p
				end
				
				document.wordcount = wc
			end
	
			-- Status bar defaults to on.

			DocumentSet.statusbar = true
		end
		
		-- Upgrade version 2 to 3.
		
		if (oldversion < 3) then
			-- Idle time defaults to 3.
			
			DocumentSet.idletime = 3
			
			-- Add the addons setting table.
			
			DocumentSet.addons = {}
		end
	end
	
	AddEventListener(Event.DocumentUpgrade, cb)
end
