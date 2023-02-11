local VFS = {};
VFS.debug=false;
VFS.Files = {
	Name="root";
	Type="Directory";
	Permissions={R=6,W=6};
	Content={};
	Lock=false;
};
VFS.CurrentUserPermissions = 6;
VFS.CurrentDirectory = VFS.Files;
VFS.CDirPath = "/";

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

local function traverseTree(path,followSymLinks,SymLinksFollowed)
	SymLinksFollowed=SymLinksFollowed or {}
	local split = path:split("/")
	--print("tt split path",split)
	local to_remove = {}
	for i,v in pairs(split) do
		if v:gsub("%s","")=="" then
			table.insert(to_remove,i)
		end
	end
	local removed = 0
	for i,v in pairs(to_remove) do
		table.remove(split,v-removed)
	end
	--print("tt AFTER split path",split)
	local last = nil
	local current = VFS.CurrentDirectory
	for i=1,#split do
		last=current
		--print('currently in "'..tostring((current or {Name='??'}).Name)..'" <'..tostring((current or {Type='??'}).Type)..">")
		if current.Type=="SymLink"then
			if followSymLinks and table.find(SymLinksFollowed,current)==nil then
				table.insert(SymLinksFollowed,current)
				local s,r = traverseTree(current.Content,followSymLinks,SymLinksFollowed)
				if s then
					current=r
					table.remove(SymLinksFollowed,#SymLinksFollowed)
				else
					break;
				end
			else
				break;
			end
		elseif current.Type=="Directory" then
			current=current.Content
			for _,v in pairs(current) do
				--print('SEARCH',v.Name,'==',split[i])
				if v.Name==split[i] then
					--print('FOUND!!!! :',v)
					current=v;break;
				end
			end
		end
		if current==nil then
			current=last
		end
		if current==last or current.Type=="File" then
			break
		end		
	end
	return current~=nil,current,last
end
local function check(perm,Name)
	local success,file = traverseTree(VFS.CDirPath..Name,true)
	--print(success,file)
	if success and file then
		local v = (file.Permissions and VFS.CurrentUserPermissions<=(file.Permissions[perm] or -10000) and not file.Lock) or (file.Permissions==nil)
		if v then
			return true
		else
			return false, "Insufficient permissions to "..(perm=="W" and "write to" or "read").." file "..tostring(Name)
		end	
	else
		return false, "Couldn't reach file "..Name..", are you sure it exists?"
	end
end

local _fileDeprecationWarning = true
local function newFile(options,c)
	if typeof(options)=="string" and typeof(c)=="string" then
		if _fileDeprecationWarning then
			warn("newFile(): overload (Name,content) is deprecated and will be removed in a future version")
			_fileDeprecationWarning=false;
		end
		options={
			Name=options;
			Type="File";
			Content=c;
			Permissions={R=6,W=6};
			Lock=false;
		}
	end
	assert(check("W",options.Name))
	for i,v in pairs(VFS.CurrentDirectory.Content) do
		if v.Name==options.Name and v.Type=="File" then
			table.remove(VFS.CurrentDirectory.Content,i);
		end
	end
	table.insert(VFS.CurrentDirectory.Content,options)
end
local _foldDeprecationWarning = true
local function newFolder(options)
	if typeof(options)=="string" then
		if _foldDeprecationWarning then
			warn("newFolder(): overload (dirname) is deprecated and will be removed in a future version")
			_foldDeprecationWarning=false;
		end
		options={
			Name=options;
			Type="Directory";
			Permissions={R=6,W=6};
			Content={};
			Lock=false;
		}
	end
	assert(check("W",options.Name))
	for i,v in pairs(VFS.CurrentDirectory.Content) do
		if v.Name==options.Name and v.Type=="Folder" then
			table.remove(VFS.CurrentDirectory.Content,i);
		end
	end
	table.insert(VFS.CurrentDirectory.Content,options)
end

VFS.writefile=newFile;
VFS.readfile=function(Name)
	assert(check("R",Name))
	local s,file = traverseTree(VFS.CDirPath..Name)
	--print(Name,s,file)
	assert(s,"Couldn't find file "..tostring(Name).." are you sure it exists?")
	return (typeof(file.Content)=="string" and file.Content or file.Content())
end
VFS.isfile=function(Name)
	if not (check("R",Name)) then return false end
	local s,file = traverseTree(VFS.CDirPath..Name)
	return s and (File(file))
end
VFS.isfolder=function(Name)
	if not (check("R",Name)) then return false end
	local s,fold = traverseTree(VFS.CDirPath..Name)
	return s and (Folder(fold))
end
VFS.rmfile=function(Name)
	assert(check("W",Name))
	local s,file,p = traverseTree(VFS.CDirPath..Name)
	assert(s,"Couldn't find file "..tostring(Name).." are you sure it exists?")
	table.remove(p,table.find(p.Content,file))
	return true
end
return function(state)
	if state==nil or type(state)~="table" then 
		state=VFS.Files 
	else
		VFS.Files=state
		VFS.CurrentDirectory=state
	end
	return VFS,state
end
