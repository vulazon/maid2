
--[[
    Cleanup Library Benchmark

    Compares the registration and cleanup performance of:
    Fang, IExplodeU, Scythe, Cleaner, Warden, Maid, and Job.
]]

local Fang = require("./comparisions/Fang")
local IExplodeU = require("./comparisions/IExplodeU")
local Job = require("./comparisions/Job")
local Cleaner = require("./comparisions/Cleaner")
local Maid = require("./comparisions/Maid")
local Scythe = require("./comparisions/Scythe")
local Warden = require("./comparisions/Warden")

local SIZE = 10000

local function noop() end

return {
	Name = "Cleanup Libraries",

	Parameter = function()
		return 0
	end,

	BeforeAll = function() end,
	AfterAll = function() end,
	BeforeEach = function() end,
	AfterEach = function() end,

	Functions = {
		["Fang"] = function(lib, _value)

			local cleaner = Fang.new()
			
			lib.profilebegin("Add")

			for _ = 1, SIZE do
				cleaner:Add(noop)
			end

			lib.profileend()

			lib.profilebegin("Clean")
			cleaner:Clean()
			lib.profileend()
			
			cleaner:Destroy()
		end,

		["IExplodeU"] = function(lib, _value)
			local scope = IExplodeU.scope()
			
			lib.profilebegin("Add")

			for _ = 1, SIZE do
				IExplodeU.add(scope, noop)
			end

			lib.profileend()

			lib.profilebegin("Clean")
			IExplodeU.clean(scope)
			lib.profileend()
			
			IExplodeU.destroy(scope)
		end,

		["Scythe"] = function(lib, _value)
			local scope = Scythe.scope()
			
			lib.profilebegin("Add")

			for _ = 1, SIZE do
				Scythe.add(scope, noop)
			end

			lib.profileend()

			lib.profilebegin("Clean")
			Scythe.clean(scope)
			lib.profileend()
			
			Scythe.destroy(scope)
		end,

		["Cleaner"] = function(lib, _value)
			local cleaner = Cleaner.new()
			
			lib.profilebegin("Add")

			for _ = 1, SIZE do
				cleaner:Add(noop)
			end

			lib.profileend()

			lib.profilebegin("Clean")
			cleaner:Cleanup()
			lib.profileend()
		end,

		["Warden"] = function(lib, _value)
			local cleaner = Warden.new()
			
			lib.profilebegin("Add")

			for _ = 1, SIZE do
				cleaner:Add(noop)
			end

			lib.profileend()

			lib.profilebegin("Clean")
			cleaner:Clean()
			lib.profileend()
			
			cleaner:Destroy()
		end,

		["Job"] = function(lib, _value)
			local cleaner = Job.new()
			
			lib.profilebegin("Add")

			for _ = 1, SIZE do
				cleaner:Add(noop)
			end

			lib.profileend()

			lib.profilebegin("Clean")
			cleaner:Clean()
			lib.profileend()
			
			cleaner:Dispose()
		end,
		
		["Maid"] = function(lib, _value)
			local cleaner = Maid.new()

			lib.profilebegin("Add")

			for _ = 1, SIZE do
				cleaner:Add(noop)
			end

			lib.profileend()

			lib.profilebegin("Clean")
			cleaner:Clean()
			lib.profileend()

			cleaner:Destroy()
		end,
	},
}
