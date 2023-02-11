local VFS
local Stream = (function()
	local function printable(st)
		return (st:gsub('[^%g]',function(s) return "\\"..string.byte(s) end))
	end
	local Event = require(script.Parent.Event)
	local M = {}
	M.__index=M
	function M.new(s,dbgn)
		return setmetatable({String=s or "";Pointer=1;_dbg=dbgn;new=function()end;Flushed=Event.new("StreamFlushed");Written=Event.new("StreamWritten")},M)
	end
	function M:read(amount)
		if self._dbg then
			print("[STRDBG]("..tostring(self._dbg)..") read("..tostring(amount)..")\n"..debug.traceback())
		end
		if amount==nil then 
			amount=1
		elseif type(amount)=="string" then
			if amount=="*l" then
				local npt = -1
				local splitted = string.split(self.String,"\n")
				for i,v in pairs(splitted) do
					if self.Pointer<#table.concat(splitted,1,i) and self.Pointer>npt then
						amount=#v
						break
					else
						npt=npt+#v
					end
				end
			elseif amount=="*a" then
				amount=#self.String-self.Pointer
			end
		end
		local result = self.String:sub(self.Pointer,self.Pointer+(amount-1))
		self.Pointer+=amount
		return result
	end
	function M:write(s)
		if self._dbg then
			print("[STRDBG]("..tostring(self._dbg)..") write("..tostring(s)..")\n"..debug.traceback())
		end
		self.String..=s
	end
	function M:seek(t,a)
		if self._dbg then
			print("[STRDBG]("..tostring(self._dbg)..") seek(",t,a,")\n"..debug.traceback())
		end
		if t==nil then t="cur" end
		if a==nil then a=0 end
		if t=="cur" then
			self.Pointer+=a
		elseif t=="end" then
			self.Pointer=#self.String+a
		elseif t=="set" then
			self.Pointer=a
		end
		return self.Pointer
	end
	function M:close()
		if self._dbg then
			print("[STRDBG]("..tostring(self._dbg)..") close()\n"..debug.traceback())
		end
		self:flush()
		self.Flushed:Destroy()
		setmetatable(self,{})
		table.clear(self)
	end
	function M:flush()
		if self._dbg then
			print("[STRDBG]("..tostring(self._dbg)..") flush()\n"..debug.traceback())
		end
		self.Flushed:Fire(self.String,self)
		-- TODO: ...
	end
	return M
end)()
local io = {_dbg={}}
function io.open(fn,s)
	if io._dbg[coroutine.running()] then
		print("[IODBG]("..tostring(io._dbg[coroutine.running()])..") open(",fn,s,")\n"..debug.traceback())
	end
	if s:find("r") then
		assert(VFS.isfile(fn),"'"..fn.."' is not a file!");
	elseif s:find("w") or s:find("a") then
		if not VFS.isfile(fn) then
			VFS.writefile(fn,"");
		end
	end	
	local handle = Stream.new(VFS.readfile(fn),io._dbg[coroutine.running()]);
	handle.Flushed:Connect(function(s)
		VFS.writefile(fn,s);
	end)
	return handle
end
function io.input(stream)
	if stream then io._streami=stream end
	return io._streami
end
function io.output(stream)
	if stream then io._streamo=stream end
	return io._streamo
end
function io.write(s)
	if io._streamo then return io._streamo:write(s) end
end
function io.read(b)
	if io._streami then return io._streami:read(b) end
end
function io.close(file)
	if file then file:close() end
end
function io.lines(file)
	file = file or io._streami
	return file:read("*a"):gmatch("([^\n]+)\n")
end
function io.remove(file)
	VFS.rmfile(file);
end
function io.flush(file)
	file:flush()	
end
local function chars(st)
	local n = {}
	for char in st:gmatch(".") do table.insert(n,char) end
	return n
end
function io.tmpfile()
	local s = ""
	local cs = chars("abcdefghijklmnopqrstuvwxyz")
	for i=1,8 do 
		s=s..cs[math.random(1,#cs)]
	end
	return io.open("/tmp/lua_"..s,"a")
end
return function(V)
	VFS=V;
	io.stderr = Stream.new("")
	io.stdin = Stream.new("")
	io.stdout = Stream.new("")
	--local s = ""
	--io.stdout.Written:Connect(function(w)
	--	if w=="\n" then
	--		print(s)
	--		s=""
	--	else
	--		s=s..w;
	--	end
	--end)
	return io
end
