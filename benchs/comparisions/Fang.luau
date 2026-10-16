--!strict
--!native
--!optimize 2

--[[
	Fang
	@author divine.no
	@date 20.09.2026
		
		
    usage;

:Add(Object) -> Object
:Remove(Object) -> bool  // untrack and clean
:Pop(Object) -> bool  // untrack only, the object stays alive
:Set(Key,Object?) -> Object?  // keyed slot, stores object and cleans whatever held the key before, Set(Key, nil) just cleans the holder
:Take(Key) -> Object?  // keyed slot, untrack only and hand the object back

^Add,Set,Take are O(1)
^Remove/Pop if object is the newest (top of the stack) -> O(1) avg. 36ns no matter how big the fang is ELSE O(n)
^- Popping the oldest object took 95 ns with 16 items, 4.3 µs with 4,096, and 74 µs with 65,536.
(can differ, measured with Lune)

:LinkToInstance(Instance) -> RBXScriptConnection  // clean when the instance is destroyed
:Clean() -> () cleans everything, fang stays usable
:Destroy()    // Clean but so a fang can sit inside a fang


^-- Fang differs from other Cleaners, how ?
- guaranteed reverse order, other cleaners clean in hash order
- safe re-entrancy
- cheaper add, one table insert with no allocation per item, trove creates a table for every add, janitor writes into hash maps
- keyed and unkeyed slots in one object


^-- No!
- never add coroutine.running() inside a thread callback

]]

type Cleanup = (...any) -> ...any

type Fields = {
	Tasks: { any },
	Keyed: { [any]: any }?,
}

type Methods = {
	__index: Methods,
	Add: <T>(self: Fang, Object: T) -> T,
	Remove: (self: Fang, Object: any) -> boolean,
	Pop: (self: Fang, Object: any) -> boolean,
	Set: <T>(self: Fang, Key: any, Object: T) -> T,
	Take: (self: Fang, Key: any) -> any,
	LinkToInstance: (self: Fang, Target: Instance) -> RBXScriptConnection,
	Clean: (self: Fang) -> (),
	Destroy: (self: Fang) -> (),
}

export type Fang = typeof(setmetatable({} :: Fields, {} :: Methods))

export type FangLibrary = {
	new: () -> Fang,
	Dispose: (Object: any) -> (),
}

local Thread = require("../thread")
local CancelTimer = Thread.Cancel
local Defer = Thread.Defer

local MAX_CLASS_DEPTH: number = 16
local MethodCache: { [any]: Cleanup } = setmetatable({}, { __mode = "k" }) :: any

local function FindClassMethod(Meta: any): Cleanup?
	local Holder = rawget(Meta, "__index")
	for _ = 1, MAX_CLASS_DEPTH do
		if type(Holder) ~= "table" then
			return nil
		end
		local Method = rawget(Holder, "Disconnect") or rawget(Holder, "Destroy")
		if Method ~= nil then
			return if type(Method) == "function" then Method else nil
		end
		local Above = getmetatable(Holder)
		if type(Above) ~= "table" then
			return nil
		end
		Holder = rawget(Above, "__index")
	end
	return nil
end

local function DisposeUncached(Object: any, Meta: any): ()
	local Method: any = Object.Disconnect or Object.Destroy
	if Method == nil then
		warn(`Fang/ {Object} has no Disconnect or Destroy method and cannot be cleaned`)
		return
	end
	if type(Meta) == "table" then
		local ClassMethod = FindClassMethod(Meta)
		if ClassMethod then
			MethodCache[Meta] = ClassMethod
		end
	end
	(Method :: Cleanup)(Object)
end

local function CancelLater(Target: thread): ()
	if coroutine.status(Target) == "suspended" then
		task.cancel(Target)
	end
end

local function DisposeBusyThread(Target: thread, Status: string): ()
	if Status ~= "dead" then
		Defer(CancelLater, Target)
	end
end

local function Dispose(Object: any): ()
	local Kind = typeof(Object)
	if Kind == "RBXScriptConnection" then
		Object:Disconnect()
	elseif Kind == "Instance" then
		Object:Destroy()
	elseif Kind == "function" then
		Object()
	elseif Kind == "table" then
		local Meta = getmetatable(Object)
		local Method = MethodCache[Meta]
		if Method then
			Method(Object)
		else
			DisposeUncached(Object, Meta)
		end
	elseif Kind == "thread" then
		local Status = coroutine.status(Object)
		if Status == "suspended" then
			task.cancel(Object)
		else
			DisposeBusyThread(Object, Status)
		end
	elseif Kind == "number" then
		CancelTimer(Object)
	elseif Kind ~= "nil" then
		warn(`Fang/ cannot clean a {Kind}: {Object}`)
	end
end

local function Clean(self: Fang): ()
	local Tasks = self.Tasks
	for Index = #Tasks, 1, -1 do
		local Object = Tasks[Index]
		Tasks[Index] = nil

		local Kind = typeof(Object)
		if Kind == "RBXScriptConnection" then
			Object:Disconnect()
			continue
		elseif Kind == "Instance" then
			Object:Destroy()
		elseif Kind == "function" then
			Object()
		elseif Kind == "table" then
			local Meta = getmetatable(Object)
			local Method = MethodCache[Meta]
			if Method then
				Method(Object)
			else
				DisposeUncached(Object, Meta)
			end
		elseif Kind == "thread" then
			local Status = coroutine.status(Object)
			if Status == "suspended" then
				task.cancel(Object)
			else
				DisposeBusyThread(Object, Status)
			end
			continue
		elseif Kind == "number" then
			CancelTimer(Object)
			continue
		elseif Kind ~= "nil" then
			warn(`Fang/ cannot clean a {Kind}: {Object}`)
		end

		if Tasks[Index] ~= nil then
			return Clean(self)
		end
	end
end

local PlainClass: Methods

local function CleanKeyed(self: Fang): ()
	local Tasks = self.Tasks
	local Map = self.Keyed :: { [any]: any }
	repeat
		Clean(self)
		for Key, Object in Map do
			Map[Key] = nil
			Dispose(Object)
		end
	until #Tasks == 0 and next(Map) == nil
	setmetatable(self :: any, PlainClass)
end

local function Add<T>(self: Fang, Object: T): T
	table.insert(self.Tasks, Object)
	return Object
end

local function Remove(self: Fang, Object: any): boolean
	local Tasks = self.Tasks
	local Top = #Tasks
	if Top > 0 and Tasks[Top] == Object then
		Tasks[Top] = nil
		Dispose(Object)
		return true
	end
	local Index = table.find(Tasks, Object)
	if Index then
		table.remove(Tasks, Index)
		Dispose(Object)
		return true
	end
	return false
end

local function Pop(self: Fang, Object: any): boolean
	local Tasks = self.Tasks
	local Top = #Tasks
	if Top > 0 and Tasks[Top] == Object then
		Tasks[Top] = nil
		return true
	end
	local Index = table.find(Tasks, Object)
	if Index then
		table.remove(Tasks, Index)
		return true
	end
	return false
end

local KeyedClass: Methods

local function SetFirst<T>(self: Fang, Key: any, Object: T): T
	if Object ~= nil then
		local Map = self.Keyed
		if Map then
			Map[Key] = Object
		else
			self.Keyed = { [Key] = Object }
		end
		setmetatable(self :: any, KeyedClass)
		table.insert(self.Tasks, self)
	end
	return Object
end

local function SetKeyed<T>(self: Fang, Key: any, Object: T): T
	local Map = self.Keyed :: { [any]: any }
	local Old = Map[Key]
	Map[Key] = Object
	if Old ~= nil and Old ~= Object then
		Dispose(Old)
	end
	return Object
end

local function TakeNone(_self: Fang, _Key: any): any
	return nil
end

local function TakeKeyed(self: Fang, Key: any): any
	local Map = self.Keyed :: { [any]: any }
	local Object = Map[Key]
	Map[Key] = nil
	return Object
end

local function LinkToInstance(self: Fang, Target: Instance): RBXScriptConnection
	local Link = Target.Destroying:Once(function()
		self:Clean()
	end)
	table.insert(self.Tasks, Link)
	return Link
end

PlainClass = {
	Add = Add,
	Remove = Remove,
	Pop = Pop,
	Set = SetFirst,
	Take = TakeNone,
	LinkToInstance = LinkToInstance,
	Clean = Clean,
	Destroy = Clean,
} :: any
PlainClass.__index = PlainClass

KeyedClass = {
	Add = Add,
	Remove = Remove,
	Pop = Pop,
	Set = SetKeyed,
	Take = TakeKeyed,
	LinkToInstance = LinkToInstance,
	Clean = CleanKeyed,
	Destroy = CleanKeyed,
} :: any
KeyedClass.__index = KeyedClass

table.freeze(PlainClass :: any)
table.freeze(KeyedClass :: any)

local function new(): Fang
	return setmetatable({ Tasks = { nil, nil, nil, nil } }, PlainClass)
end

return table.freeze({
	new = new,
	Dispose = Dispose,
} :: FangLibrary)
