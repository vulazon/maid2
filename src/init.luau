--!strict
--!native
--!optimize 2

--[[
    Maid2
    - @n.iru

    Cleanup manager
]]

-- TYPES --
type Fields = {
	Tasks: { any },
	Cleaning: boolean,
	Destroying: boolean,
}

type Methods = {
	__index: Methods,
	new: () -> Maid,
	Add: <T>(self: Maid, object: T & Trackable) -> T,
	Remove: <T>(self: Maid, object: T & Trackable) -> boolean,
	Pop: <T>(self: Maid, object: T & Trackable) -> boolean,
	AttachToInstance: <T>(self: Maid, object: T & Trackable) -> RBXScriptConnection,
	Schedule: (self: Maid, delay: number?, fn: fn) -> thread,
	Construct: <T, A...>(self: Maid, class: Constructable<T, A...>, A...) -> T,
	Extend: (self: Maid, destroyWhenCleaned: boolean?) -> Maid, -- final function im adding after construct so this wont be as bloated but good
	Connect: (
		self: Maid,
		signal: SignalLike | SignalLikeMetatable | RBXScriptSignal,
		fn
	) -> ConnectionLike | ConnectionLikeMetatable | RBXScriptConnection,
	Once: (
		self: Maid,
		signal: SignalLike | SignalLikeMetatable | RBXScriptSignal,
		fn
	) -> ConnectionLike | ConnectionLikeMetatable | RBXScriptConnection,
	Clean: (self: Maid) -> (),
	Destroy: (self: Maid) -> (),
}

export type Maid = typeof(setmetatable({} :: Fields, {} :: Methods))

export type Trackable =
	| Instance
	| RBXScriptConnection
	| ConnectionLike
	| ConnectionLikeMetatable
	| thread
	| ((...any) -> ...any)
	| Destroyable
	| DestroyableMetatable
	| DestroyableLowercase
	| DestroyableLowercaseMetatable
	| Disconnectable
	| DisconectableMetatable
	| DisconnectableLowercase
	| DisconnectableLowercaseMetatable
	| SignalLike
	| SignalLikeMetatable

type Constructable<T, A...> = { new: (A...) -> T } | (A...) -> T

type ConnectionLike = {
	Connected: boolean,
	Disconnect: (self: ConnectionLike) -> (),
}

type ConnectionLikeMetatable = typeof(setmetatable(
	{},
	{} :: { Connected: boolean, Disconnect: (self: ConnectionLikeMetatable) -> () }
))

type SignalLike = {
	Connect: (self: SignalLike, callback: (...any) -> ...any) -> ConnectionLike | ConnectionLikeMetatable,
	Once: (self: SignalLike, callback: (...any) -> ...any) -> ConnectionLike | ConnectionLikeMetatable,
}

type SignalLikeMetatable = typeof(setmetatable(
	{},
	{} :: {
		Connect: (self: SignalLikeMetatable, callback: (...any) -> ...any) -> ConnectionLike | ConnectionLikeMetatable,
		Once: (self: SignalLikeMetatable, callback: (...any) -> ...any) -> ConnectionLike | ConnectionLikeMetatable,
	}
))

type Destroyable = {
	Destroy: (self: Destroyable) -> (),
}

type DestroyableMetatable = typeof(setmetatable({}, {} :: { Destroy: (self: DestroyableMetatable) -> () }))

type DestroyableLowercase = {
	destroy: (self: DestroyableLowercase) -> (),
}

type DestroyableLowercaseMetatable = typeof(setmetatable(
	{},
	{} :: { destroy: (self: DestroyableLowercaseMetatable) -> () }
))

type Disconnectable = {
	Disconnect: (self: Disconnectable) -> (),
}

type DisconectableMetatable = typeof(setmetatable({}, {} :: { Disconnect: (self: DisconectableMetatable) -> () }))

type DisconnectableLowercase = {
	disconnect: (self: DisconnectableLowercase) -> (),
}

type DisconnectableLowercaseMetatable = typeof(setmetatable(
	{},
	{} :: { disconnect: (self: DisconnectableLowercaseMetatable) -> () }
))

type fn = (...any) -> ...any

-- VARIABLES --
local thread = require("@self/thread")
local maxClassDepth = 16
local methodCache: { [any]: fn } = setmetatable({}, { __mode = "k" }) :: any

-- PRIVATE METHODS --
local function findClassMethod(meta: any): fn?
	local holder = rawget(meta, "__index")

	for _ = 1, maxClassDepth do
		if type(holder) ~= "table" then
			return nil
		end

		local method = rawget(holder, "Disconnect") or rawget(holder, "Destroy")

		if method ~= nil then
			return typeof(method) == "function" and method or nil
		end

		local above = getmetatable(holder)

		if type(above) ~= "table" then
			return nil
		end

		holder = rawget(above, "__index")
	end

	return nil
end

local function assertSignalLike(object: any)
	if
		typeof(object) ~= "RBXScriptSignal"
		and (typeof(object) ~= "table" or typeof(object.Connect) ~= "function" or typeof(object.Once) ~= "function")
	then
		error("did not receive an signal as a argumet")
	end
end

local function cancelLater(target: thread)
	if coroutine.status(target) == "suspended" then
		task.cancel(target)
	end
end

local function destroyUncached(object: any, meta: any)
	local method: any = object.Disconnect or object.Destroy

	if not method then
		return warn(`{object} has no Disconnect/Destroy function and can't be cleaned`)
	end

	if type(meta) == "table" then
		local classMethod = findClassMethod(meta)

		if classMethod then
			methodCache[meta] = classMethod
		end
	end

	(method :: fn)(object)
end

local function dispose(i: any)
	local t = typeof(i)

	if t == "RBXScriptConnection" then
		if i.Connected then
			i:Disconnect()
		end
	elseif t == "Instance" then
		i:Destroy()
	elseif t == "function" then
		i()
	elseif t == "table" then
		local meta = getmetatable(i)
		local method = methodCache[meta]
		if method then
			method(i)
		else
			destroyUncached(i, meta)
		end
	elseif t == "thread" then
		const status = coroutine.status(i)
		if status == "suspended" then
			task.cancel(i)
		elseif status ~= "dead" then
			thread.Defer(cancelLater, i)
		end
	elseif t == "userdata" then
		const target = i :: any
		const method = (target.Destroy or target.Disconnect) :: fn
		if type(method) == "function" then
			method(target)
		end
	elseif t ~= nil then
		warn(`Maid2 cannot clean {t}: {i}`)
	end
end

local function remove(self: Maid, object: Trackable)
	local tasks = self.Tasks
	local top = #tasks

	if top > 0 and tasks[top] == object then
		tasks[top] = nil
		dispose(object)
		return true
	end

	local i = table.find(tasks, object)

	if i then
		table.remove(tasks, i)
		dispose(object)
		return true
	end

	return false
end

local function pop(self: Maid, object: any)
	local tasks = self.Tasks
	local top = #tasks

	if top > 0 and tasks[top] == object then
		tasks[top] = nil
		return true
	end

	local i = table.find(tasks, object)

	if i then
		table.remove(tasks, i)
		return true
	end

	return false
end

local function connect(self: Maid, object: SignalLike | SignalLikeMetatable, fn: fn)
	if self.Destroying then
		error("attempting to call a maid function while destroying it")
	end

	assertSignalLike(object)

	local _s = object :: SignalLike

	local connection = _s:Connect(fn)

	table.insert(self.Tasks, connection)

	return connection
end

local function schedule(self: Maid, delay: number?, fn: fn)
	if self.Destroying then
		error("attempting to call a maid function while destroying it")
	end

	local t
	t = task.delay(delay or 3, function(...)
		pop(self, t)
		fn(...)
	end)

	table.insert(self.Tasks, t)

	return t
end

local function once(self: Maid, object: SignalLike | SignalLikeMetatable, fn: fn)
	if self.Destroying then
		error("attempting to call a maid function while destroying it")
	end

	assertSignalLike(object)

	local _s = object :: SignalLike

	local connection
	connection = _s:Once(function(...)
		pop(self, connection)
		fn(...)
	end)

	table.insert(self.Tasks, connection)

	return connection
end

local function construct<T, A...>(self: Maid, constructable: Constructable<T, A...>, ...: A...)
	if self.Destroying then
		error("attempting to call a maid function while destroying it")
	end

	local o
	local t = typeof(constructable)

	if t == "table" then
		o = (constructable :: any).new(...)
	elseif t == "function" then
		o = (constructable :: any)(...)
	end

	table.insert(self.Tasks, o)

	return o
end

-- MAID --
local Maid = {} :: Methods
Maid.__index = Maid

Maid.Pop = pop
Maid.Remove = remove
Maid.Connect = connect
Maid.Construct = construct
Maid.Once = once
Maid.Schedule = schedule

function Maid.new(): Maid
	local self: Maid = setmetatable({ Tasks = { nil, nil, nil, nil, nil }, Cleaning = false, Destroying = false }, Maid)

	return self
end

function Maid.Destroy(self: Maid)
	if self.Destroying then
		return
	end

	self.Destroying = true

	if self.Cleaning then
		repeat
			task.wait()
		until not self.Cleaning -- unsafe but im keeping this here regardless
	else
		self:Clean()
	end

	table.clear(self.Tasks)
	table.clear(self)

	setmetatable(self, nil)
end

function Maid.Add(self: Maid, object: Trackable)
	if self.Destroying then
		error("attempting to a maid function while destroying it")
	end

	table.insert(self.Tasks, object)

	return object
end

function Maid.AttachToInstance(self: Maid, object: Instance) -- disallow this during cleanup
	if self.Destroying then
		error("attempting to a maid function while destroying it")
	end

	if self.Cleaning then
		error("attempting to call a maid function during cleanup")
	end

	local connection = object.Destroying:Once(function()
		self:Clean()
	end)

	table.insert(self.Tasks, connection)

	return connection
end

function Maid.Extend(self: Maid, destroyWhenCleaned: boolean)
	if self.Destroying then
		error("attempting to a maid function while destroying it")
	end

	local new = construct(self, Maid) :: Maid

	if destroyWhenCleaned then
		table.insert(new.Tasks, function()
			pop(self, new)
			Maid.Destroy(new)
		end)
	else
		table.insert(new.Tasks, function()
			Maid.Destroy(new)
		end)
	end

	return new
end

function Maid.Clean(self: Maid)
	if self.Cleaning then
		return
	end

	self.Cleaning = true

	local tasks = self.Tasks

	for index = #tasks, 1, -1 do
		local i = tasks[index]
		local t = typeof(i)
		tasks[index] = nil

		if t == "Instance" then
			i:Destroy()
		elseif t == "function" then
			i()
		elseif t == "table" then
			local meta = getmetatable(i)
			local method = methodCache[meta]
			if method then
				method(i)
			else
				destroyUncached(i, meta)
			end
		elseif t == "RBXScriptConnection" then
			if i.Connected then
				i:Disconnect()
			end
		elseif t == "thread" then
			const status = coroutine.status(i)
			if status == "suspended" then
				task.cancel(i)
			elseif status ~= "dead" then
				thread.Defer(cancelLater, i)
			end
		elseif t == "userdata" then
			const target = i :: any
			const method = (target.Destroy or target.Disconnect) :: fn
			if type(method) == "function" then
				method(target)
			end
		elseif t ~= nil then
			warn(`Maid2 cannot clean {t}: {i}`)
		end

		if tasks[index] ~= nil then
			self.Cleaning = false
			return Maid.Clean(self)
		end
	end

	self.Cleaning = false
end

table.freeze(Maid)

return table.freeze({
	new = Maid.new,
})
