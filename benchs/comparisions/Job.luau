--!strict
--!optimize 2
--!native

--[[
    @n.iru
    Job - trove but like with some improvements and a bit of features
    this is old and not recommended to use DONT DONT USEEEE USE MAID OVER THISS
]]

local thread = require("../thread")
local runService = game:GetService("RunService")

-- types --

export type Job = {
	Extend: <T>(self: Job, removeWhenCleaned: boolean?) -> Job, -- removeWhenCleaned is short for Job:Add(function() parentJob:Pop(Job) end)
	Clone: <T>(self: Job, object: T & Trackable) -> T,
	Construct: <T, A...>(self: Job, class: Constructable<T, A...>, A...) -> T,
	Connect: (
		self: Job,
		signal: SignalLike | SignalLikeMetatable | RBXScriptSignal,
		fn: (...any) -> ()
	) -> ConnectionLike | ConnectionLikeMetatable,
	Once: (
		self: Job,
		signal: SignalLike | SignalLikeMetatable | RBXScriptSignal,
		fn: (...any) -> ()
	) -> ConnectionLike | ConnectionLikeMetatable,
	BindToRenderStep: (self: Job, name: string, priority: number, fn: (dt: number) -> ()) -> (),
	Add: <T>(self: Job, object: T & Trackable) -> T,
	AddPromise: <T>(self: Job, Promise: PromiseLike | PromiseLikeMetatable) -> T,
	Remove: <T>(self: Job, object: T & Trackable) -> boolean,
	Pop: <T>(self: Job, object: T & Trackable) -> boolean,
	AttachToInstance: <T>(self: Job, object: T & Trackable) -> RBXScriptConnection,
	Clean: (self: Job) -> (),
	WrapClean: (self: Job) -> () -> (),
	Destroy: (self: Job) -> (),
	Dispose: (self: Job) -> (), -- Cleans all tasks and destroys the job object. (better to use instead of leaving it for the gc)

	-- THREAD FUNCTIONS --
	Schedule: (self: Job, delay: number, fn: (...any) -> ()) -> thread, -- short for Job:Add(task.delay)
}

export type JobInternal = Job & {
	_objects: {
		[number]: any
	},
	_cleaning: boolean,
	_disposing: boolean,
	_findAndRemoveFromObjects: (self: Job, object: any, cleanUp: boolean?) -> boolean,
	_cleanupObject: (self: Job, object: any, cleanupMethod: string?) -> (),
}

type Constructable<T, A...> = { new: (A...) -> T } | (A...) -> T

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
| PromiseLike
| PromiseLikeMetatable

type ConnectionLike = {
	Connected: boolean,
	Disconnect: (self: ConnectionLike) -> (),
}

type PromiseLike = {
	getStatus: (self: PromiseLike) -> string,
	finally: (self: PromiseLike, callback: (...any) -> ...any) -> PromiseLike | PromiseLikeMetatable,
	cancel: (self: PromiseLike) -> (),
}

type PromiseLikeMetatable = typeof(setmetatable(
	{},
	{} :: {
		getStatus: (self: any) -> string,
		finally: (self: PromiseLikeMetatable, callback: (...any) -> ...any) -> PromiseLike | PromiseLikeMetatable,
		cancel: (self: PromiseLikeMetatable) -> (),
	}
	))

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

-- PRIVATE METHODS --
local fn_marker = "_"
local thread_marker = "__"
local generic_object_cleanup_methods =
	table.freeze({ "Destroy", "Disconnect", "destroy", "disconnect", "clean", "Clean" })

local function getObjectCleanupFunction(object: any, cleanupMethod: string?)
	local t = typeof(object)

	if t == "function" then
		return fn_marker
	elseif t == "thread" then
		return thread_marker
	end

	if cleanupMethod then
		return cleanupMethod
	end

	if t == "Instance" then
		return "Destroy"
	elseif t == "RBXScriptConnection" then
		return "Disconnect"
	elseif t == "table" then
		for _, v in ipairs(generic_object_cleanup_methods) do
			if not object[v] then
				continue
			end

			if typeof(object[v]) == "function" then
				return v
			end
		end
	end
	
	error(`failed to get cleanup function for object {t}: {object}`, 3)
end

local function assertPromiseLike(object: any)
	if
		typeof(object) ~= "table"
		or typeof(object.getStatus) ~= "function"
		or typeof(object.finally) ~= "function"
		or typeof(object.cancel) ~= "function"
	then
		error("did not receive a promise as an argument", 3)
	end
end

local function assertSignalLike(object: any)
	if
		typeof(object) ~= "RBXScriptSignal"
		and (typeof(object) ~= "table" or typeof(object.Connect) ~= "function" or typeof(object.Once) ~= "function")
	then
		error("did not receive a signal as an argument", 3)
	end
end

--[=[
    @class Job
    constructs a new job object
]=]
local Job = {}

function Job.new(): Job
	local self = {
		_objects = {},
		_cleaning = false,
		_disposing = false,
		_findAndRemoveFromObjects = Job._findAndRemoveFromObjects,
		_cleanupObject = Job._cleanupObject,
		Add = Job.Add,
		Remove = Job.Remove,
		Pop = Job.Pop,
		AddPromise = Job.AddPromise,
		Extend = Job.Extend,
		Construct = Job.Construct,
		Destroy = Job.Destroy,
		Clean = Job.Clean,
		WrapClean = Job.WrapClean,
		Schedule = Job.Schedule,
		BindToRenderStep = Job.BindToRenderStep,
		Dispose = Job.Dispose,
		AttachToInstance = Job.AttachToInstance,
		Clone = Job.Clone,
		Connect = Job.Connect,
		Once = Job.Once,
	} :: JobInternal

	return self
end

function Job._findAndRemoveFromObjects(self: JobInternal, object: any, cleanup: boolean): boolean
	local objects = self._objects

	-- replaced with a WAY faster lookup in my opinion, untested but this shouldnt take alot of time to find a object when theres more than 100 tasks

	local i = table.find(objects, object)

	if i then
		table.remove(objects, i)

		if cleanup then
			self:_cleanupObject(object, getObjectCleanupFunction(object))
		end

		return true
	end

	return false
end

function Job._cleanupObject(_self: JobInternal, object: any, cleanupMethod: string?)
	if cleanupMethod == fn_marker then
		xpcall(object, warn) -- can't risk erroring while cleaning lolol
	elseif cleanupMethod == thread_marker then
		pcall(task.cancel, object)
	else
		xpcall(object[cleanupMethod], warn, object)
	end
end

function Job.Add(self: JobInternal, object: Trackable): any
	if self._cleaning then
		error("cannot call job:Add while cleaning", 2)
	end

	self._objects[#self._objects + 1] = object

	return object
end

function Job.Clone(self: JobInternal, object: Instance): Instance
	if self._disposing then
		error("cannot call job functions when disposing", 3)
	end

	if self._cleaning then
		error("cannot call job:Clone while cleaning", 2)
	end

	return self:Add(object:Clone())
end

function Job.Construct<T, A...>(self: JobInternal, class: Constructable<T, A...>, ...: A...)
	if self._disposing then
		error("cannot call job functions when disposing", 3)
	end

	if self._cleaning then
		error("cannot call job:Construct while cleaning", 2)
	end

	local object = nil
	local t = typeof(class)
	if t == "table" then
		object = (class :: any).new(...)
	elseif t == "function" then
		object = (class :: any)(...)
	end

	return self:Add(object)
end

function Job.Extend(self: JobInternal, removeWhenCleaned: boolean): Job
	if self._disposing then
		error("cannot call job functions when disposing", 3)
	end

	if self._cleaning then
		error("cannot call job:Extend while cleaning", 2)
	end

	local subJob: Job = self:Construct(Job) :: Job

	if removeWhenCleaned then
		subJob:Add(function()
			if not self._cleaning then
				self:_findAndRemoveFromObjects(subJob, false)
			end

			subJob:Dispose()
		end)
	else
		subJob:Add(function()
			subJob:Dispose() -- dispose of it because theres no point in keeping it when its no longer attached to the parent job
		end)
	end

	return subJob
end

function Job.Connect(
	self: JobInternal,
	signal: SignalLike | SignalLikeMetatable | RBXScriptSignal,
	fn: (...any) -> ...any
)
	if self._disposing then
		error("cannot call job functions when disposing", 3)
	end

	if self._cleaning then
		error("cannot call job:Connect while cleaning", 2)
	end
	assertSignalLike(signal)

	local confirmedSignal = signal :: SignalLike

	return self:Add(confirmedSignal:Connect(fn))
end

function Job.Once(self: JobInternal, signal: SignalLike | SignalLikeMetatable | RBXScriptSignal, fn: (...any) -> ...any)
	if self._disposing then
		error("cannot call job functions when disposing", 3)
	end

	if self._cleaning then
		error("cannot call job:Once while cleaning", 2)
	end
	assertSignalLike(signal)

	local confirmedSignal = signal :: SignalLike

	local conn: ConnectionLike | ConnectionLikeMetatable
	conn = confirmedSignal:Once(function(...)
		self:_findAndRemoveFromObjects(conn, false)
		fn(...)
	end)

	return self:Add(conn)
end

function Job.Schedule(self: JobInternal, delay: number, fn: (...any) -> ()): thread
	if self._disposing then
		error("cannot call job functions when disposing", 3)
	end

	if self._cleaning then
		error("cannot call job:Schedule while cleaning", 2)
	end

	local scheduled: thread
	scheduled = self:Add(task.delay(delay or 3, function(...)
		self:_findAndRemoveFromObjects(scheduled, false)
		fn(...)
	end))

	return scheduled
end

function Job.AttachToInstance(
	self: JobInternal,
	object: Instance
): ConnectionLike | ConnectionLikeMetatable | RBXScriptConnection
	if self._disposing then
		error("cannot call job functions when disposing", 3)
	end

	if self._cleaning then
		error("cannot call job:AttachToInstance while cleaning", 2)
	elseif not object:IsDescendantOf(game) then
		error("instance is not inside the game hierarchy", 2)
	end

	return self:Connect(object.Destroying, function()
		self:Clean()
	end)
end

function Job.AddPromise(self: JobInternal, Promise: PromiseLike | PromiseLikeMetatable)
	if self._disposing then
		error("cannot call job functions when disposing", 3)
	end

	if self._cleaning then
		error("cannot call job:AddPromise while cleaning", 2)
	end
	assertPromiseLike(Promise)

	local fixPromise = Promise :: PromiseLike -- KILL THE TYPECHECKER

	if fixPromise:getStatus() == "Started" then
		fixPromise:finally(function()
			if not self._cleaning then
				self:_findAndRemoveFromObjects(fixPromise, false)
			end
		end)

		self:Add(fixPromise)
	end

	return fixPromise
end

function Job.Dispose(self: JobInternal)
	if self._disposing then
		return
	end

	self._disposing = true

	thread.Spawn(function()
		if self._cleaning then
			repeat
				runService.Heartbeat:Wait()
			until not self._cleaning -- dont clean again lol
		else
			self:Clean()
		end

		table.clear(self._objects)
		table.clear(self) -- we dont use metatables so theres no reason to use setmetatable
	end)
end

function Job.Clean(self: JobInternal)
	if self._cleaning then
		return
	end

	self._cleaning = true

	local objects = self._objects

	for i = #objects, 1, -1 do
		local _task = objects[i]
		
		self:_cleanupObject(_task, getObjectCleanupFunction(_task))

		objects[i] = nil
	end

	self._cleaning = false
end

function Job.BindToRenderStep(self: JobInternal, name: string, priority: number, func: (dt: number) -> ())
	if self._disposing then
		error("cannot call job functions when disposing", 3)
	end

	if self._cleaning then
		error("cannot call Job:BindToRenderStep while cleaning", 2)
	elseif runService:IsServer() then
		error("cannot call Job:BindToRenderStep on server", 3)
	end

	runService:BindToRenderStep(name, priority, func)

	self:Add(function()
		runService:UnbindFromRenderStep(name)
	end)
end

function Job.WrapClean(self: JobInternal): () -> () -- this is useless icl i might remove it
	return function()
		self:Clean() 
	end
end

function Job.Destroy(self: JobInternal)
	self:Clean()
end

function Job.Remove(self: JobInternal, object: Trackable): boolean
	if self._disposing then
		error("cannot call job functions when disposing", 3)
	end

	if self._cleaning then
		error("cannot call job:Remove while cleaning", 2)
	end

	return self:_findAndRemoveFromObjects(object, true)
end

function Job.Pop(self: JobInternal, object: Trackable): boolean
	if self._disposing then
		error("cannot call job functions when disposing", 3)
	end

	if self._cleaning then
		error("cannot call job:Pop while cleaning", 2)
	end

	return self:_findAndRemoveFromObjects(object, false)
end

return table.freeze({
	new = Job.new,
})
