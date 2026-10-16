--!strict

const function CleanObject(object: Trackable | any, objectType: string): ()
	if objectType == "table" then
		const cleanupMethod: CustomTask = object.Destroy or object.Disconnect
		if typeof(cleanupMethod) == "function" then
			cleanupMethod(object)
			return
		end
		warn("[WARDEN]:", object, "is missing a cleanup method and cannot be cleaned!")
	elseif objectType == "Instance" then
		object:Destroy()
	elseif objectType == "RBXScriptConnection" then
		object:Disconnect()
	elseif objectType == "function" then
		object()
	elseif objectType == "thread" then
		if coroutine.status(object) == "suspended" then
			task.cancel(object)
		end
	else
		warn("[WARDEN]:", objectType, "is an unsupported type and cannot be cleaned!")
	end
end

const Warden = {}
Warden.__index = Warden

export type Warden = setmetatable<{ Trackable }, typeof(Warden)>
export type Trackable = Instance | RBXScriptConnection | thread | CustomTask | MetatableTask | () -> ()
type CustomTask = { Destroy: (self: CustomTask) -> (), Disconnect: (self: CustomTask) -> () }
type MetatableTask = setmetatable<{}, { Destroy: (self: MetatableTask) -> (), Disconnect: (self: MetatableTask) -> () }>

--[[Constructs a Warden object]]
const function new(): Warden
	return setmetatable({}, Warden)
end

--[[Cleans up the object passed]]
const function Dispose(object: Trackable): ()
	CleanObject(object, typeof(object))
end

--[[Adds an object to be cleaned & returns it]]
function Warden.Add<T>(self: Warden, object: T & Trackable): T
	table.insert(self, object)
	return object
end

--[[Removes the object if tracked, is not cleaned upon removal]]
function Warden.Remove(self: Warden, object: Trackable): ()
	const index = table.find(self, object)
	if index then
		table.remove(self, index)
	end
end

--[[Removes the object if tracked & is cleaned upon removal]]
function Warden.Dispose(self: Warden, object: Trackable): ()
	const index = table.find(self, object)
	if index then
		table.remove(self, index)
		CleanObject(object, typeof(object))
	end
end

--[[Cleans up all tracked objects]]
function Warden.Clean(self: Warden): ()
	for _, object in self do
		CleanObject(object, typeof(object))
	end
	table.clear(self)
end

Warden.Destroy = Warden.Clean

return { new = new, Dispose = Dispose }
