--[[ 
#   EIBD client library
#   Copyright (C) 2005-2011 Martin Koegler <mkoegler@auto.tuwien.ac.at>
# 
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
# 
#   In addition to the permissions in the GNU General Public License, 
#   you may link the compiled version of this file into combinations
#   with other programs, and distribute those combinations without any 
#   restriction coming from the use of this file. (The General Public 
#   License restrictions do apply in other respects; for example, they 
#   cover modification of the file, and distribution when not linked into 
#   a combine executable.)
# 
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
# 
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
# 
]]

--import errno;
--import socket;
require("socket");
require("bit");

EIBBuffer = {};
function EIBBuffer.new(self, buf)
    self = self or {}
    self.buffer = buf or {};
    return self
end

EIBAddr = {};
function EIBAddr.new(self, value)
	error "FIXME"
    self.data = value or 0
end

EIBInt8 = {};
function EIBInt8.new(self, value)
	error "FIXME"
    self.data = value or 0
end

EIBInt16 = {};
function EIBInt16.new(self, value)
	error "FIXME"
    self.data = value or 0
end

EIBInt32 = {};
function EIBInt32.new(self, value)
	error "FIXME"
    self.data = value or 0
    return self
end

EIBConnection = {};
function EIBConnection:new(o)
print ("New EIBConnection")
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self.data = {}
    self.readlen = 0
    self.datalen = 0
    self.fd = None
    self.errno = 0
    self.__complete = nil
    return o
end

function EIBConnection.EIBSocketLocal(self, path)
    if (self.fd ~= nil) then
      self.errno = "EUSERS"
      return -1
    end
    fd = socket.unix()
    fd:connect(path)
    self.data = {}
    self.readlen = 0
    self.fd = fd
    return 0
end

function EIBConnection.EIBSocketRemote(self, host, port)
    if (self.fd ~= nil) then
      self.errno = "EUSERS"
      return -1
  end
  port = port or 6720
  fd = socket.tcp()
  -- convert host name to ip address

  --FIXME: resolve hostname if not an IP address already
  -- local host = socket.dns.toip(host)
	hostip = host
	print("hostip=",hostip)
  fd:connect(hostip, port);
  self.data = {}
  self.readlen = 0
  self.fd = fd
  return 0
end

function EIBConnection.EIBSocketURL(self, url)
if DEBUG then print(url) end
    if (url:sub(0,6) == 'local:') then
      return self.EIBSocketLocal(url:sub(6))
    end
    if (url:sub(0,3) == 'ip:') then 
------ parts=url.split(':')
      hostport = url:sub(4,-1)
      host, port = nil, nil
      offset = hostport:find(":")
      if (offset) then
	  host = hostport:sub(1, offset)
	  port = tonumber(hostport:sub(offset+1))
	else
	  host = hostport
          port = 6720
      end
	print("host=",host," port=",port)
      return self:EIBSocketRemote(host, port)
    end
    self.errno = "EINVAL"
    return -1
end
  
function EIBConnection.EIBComplete(self)
  if DEBUG then   print("Entering EIBConnection.EIBComplete()") end
    if self.__complete == nil then
      self.errno = "EINVAL"
      return -1
    end
    return self.__complete
end
  
function EIBConnection.EIBClose(self)
  if DEBUG then print("Entering EIBConnection.EIBClose()") end
    if self.fd == nil then
      self.errno = "EINVAL"
      return -1
    end
    self.fd:close()
    self.fd = nil
end

function EIBConnection.EIBClose_sync(self)
  if DEBUG then print("Entering EIBConnection.EIBClose_sync()") end
    self.EIBReset()
    return self.EIBClose()
end

function EIBConnection.__EIB_SendRequest(self, data)
-- EKARAK: MUST DECLARE ALL LOCAL VARIABLES, OR ELSE THEY POLLUTE GLOBAL NAMESPACE
  local result, errmsg, data2
  if DEBUG then print("Entering EIBConnection.__EIB_SendRequest()") end
  --print(dump(data))
    if type(data) == "table" then
	result = ""
        for i = 1, #data do
            result = result .. string.char(data[i])
        end
        data = result
	--data = table.concat(data)
    end
    if self.fd == nil then
      self.errno = "ECONNRESET"
      return -1
    end
    if (#(data) < 2 or #(data) > 0xffff) then
      self.errno = "EINVAL"
      return -1
    end
    -- data = [ (len(data)>>8)&0xff, (len(data))&0xff ] + data
    data2 = string.char( bit.band ( bit.rshift(#data,8) , 0xff )) .. string.char( bit.band (#(data), 0xff) ) .. data
    for i=1,#data2 do self.data[i] = data2:byte(i) end
	if DEBUG then print("EIBConnection.__EIB_SendRequest() sending:", hex_dump(data2)) end
    result, errmsg = self.fd:send(data2)
	if not result then
		error("connection error: "..errmsg)
		os.exit()
	end
    return 0
end
  
  
function EIBConnection.EIB_Poll_FD(self)
  if DEBUG then print("Entering EIBConnection.EIB_Poll_FD()") end
    if self.fd == nil then
      self.errno = "EINVAL"
      return -1
    end
    return self.fd
end
  
function EIBConnection.EIB_Poll_Complete(self)
  if DEBUG then print("Entering EIBConnection.EIB_Poll_Complete()") end
    if self.__EIB_CheckRequest(false) == -1 then
      return -1
    end
    if self.readlen < 2 or (self.readlen >= 2 and self.readlen < self.datalen + 2) then
      return 0
    end
    return 1
end
  
function EIBConnection.__EIB_GetRequest(self)
  if DEBUG then   print("Entering EIBConnection.__EIB_GetRequest()") end
     while true do
      if self:__EIB_CheckRequest(true) == -1 then
        return -1
      end
	if DEBUG then print(string.format("__EIB_GetRequest, self.readlen=%d self.datalen=%d", self.readlen, self.datalen)) end
      if (self.readlen >= 2) and (self.readlen >= self.datalen + 2) then
        self.readlen = 0
        return 0
      end
    end
end

function EIBConnection.__EIB_CheckRequest(self, block)
-- EKARAK: MUST DECLARE ALL LOCAL VARIABLES, OR ELSE THEY POLLUTE GLOBAL NAMESPACE
  local result, errmsg
--
  if DEBUG then print("Entering EIBConnection.__EIB_CheckRequest()") end
    if self.fd == nil then
      self.errno = "ECONNRESET"
      return -1
    end
    if self.readlen == 0 then
      self.head = {}
      self.data = {}
    end
    if self.readlen < 2 then
--      self.fd:setblocking(block)
	if block then
	  self.fd:settimeout(1)
	else 
	  self.fd:settimeout(3)
	end
      result, errmsg = self.fd:receive(2-self.readlen)
	if result then
		if DEBUG then print(string.format("received %d bytes: %s", #result, hex_dump(result))) end
		oldlen = #(self.head)
		self.readlen = self.readlen + #result -- yucks yucks YUCKS
		--print("self.readlen == ", self.readlen, "type(#result)==",type(#result))		
		for i=1,#result do table.insert(self.head, result:byte(i)) end
		--print("self.head dump:", hex_dump(self.head))
	else 
		print("ERROR receing: errmsg=", errmsg)
		os.exit()
	end
    end
    if self.readlen < 2 then
      return 0
    end
    -----self.datalen = (self.head[0] << 8) | self.head[1]
    self.datalen = bit.bor( bit.lshift(self.head[1] , 8),  self.head[2])

    if DEBUG then print(string.format("__EIB_CheckRequest stage 2, self.readlen=%d self.datalen=%d", self.readlen, self.datalen)) end
    if (self.readlen < self.datalen + 2) then
	if block then
	  self.fd:settimeout(1)
	else 
	  self.fd:settimeout(3)
	end
      result, errmsg = self.fd:receive(self.datalen + 2 -self.readlen)
	if result then
		if DEBUG then print(string.format("received %d bytes: %s", #result, hex_dump(result))) end
		oldlen = #(self.data)
		self.readlen = self.readlen + #result -- yucks yucks YUCKS
		-- ekarak: YUCKS! 
		for i=1,#result do 
			table.insert(self.data, result:byte(i)) 
		end
	else 
		print("ERROR receing: errmsg=", errmsg)
		os.exit()
	end
    end
    return 0      
end


-- HELPER FUNCTIONS
function hex_dump(buf)
    result = ""
    for i=1,math.ceil(#buf/16) * 16 do
     	if (i-1) % 16 == 0 then result = result..(string.format('%08X  ', i-1)) end
	foo, bar = "", ""
	if type(buf) == "string" then 
		foo = buf:byte(i)
		bar = buf:sub(i-16+1, i):gsub('%c','.')
	elseif type(buf) == "table" then 
		foo = buf[i]
		bar = table.concat(buf):sub(i-16+1, i):gsub('%c','.')
	end
        result = result..( i > #buf and '   ' or string.format('%02X ', foo) )
        if i %  8 == 0 then result = result..(' ') end
        if i % 16 == 0 then result = result..bar..'\n' end
     end
     return result
end

function EIBConnection.__EIBGetAPDU_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBGetAPDU_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 37) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    self.buf.buffer = self.data:sub(2)
    return #(self.buf.buffer)

end

function EIBConnection.EIBGetAPDU_async(self, buf)
  if DEBUG then print("Entering EIBConnection.EIBGetAPDU_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    self.buf = buf
    self.__complete = self:__EIBGetAPDU_Complete();
    return 0
end

function EIBConnection.EIBGetAPDU(self, buf)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBGetAPDU()") end
    if self:EIBGetAPDU_async (buf) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBGetAPDU_Src_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBGetAPDU_Src_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 37) or (#(self.data) < 4) then 
      self.errno = "ECONNRESET"
      return -1
    end
    if self.ptr5 ~= nil then
      self.ptr5.data =  bit.bor(  bit.lshift(self.data[2+1], 8) , (self.data[2+2]))
    end
    self.buf.buffer = self.data:sub(4)
    return #(self.buf.buffer)

end

function EIBConnection.EIBGetAPDU_Src_async(self, buf, src)
  if DEBUG then print("Entering EIBConnection.EIBGetAPDU_Src_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    self.buf = buf
    self.ptr5 = src
    self.__complete = self:__EIBGetAPDU_Src_Complete();
    return 0
end

function EIBConnection.EIBGetAPDU_Src(self, buf, src)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBGetAPDU_Src()") end
    if self:EIBGetAPDU_Src_async (buf, src) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBGetBusmonitorPacket_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBGetBusmonitorPacket_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 20) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    self.buf.buffer = self.data:sub(2)
    return #(self.buf.buffer)

end

function EIBConnection.EIBGetBusmonitorPacket_async(self, buf)
  if DEBUG then print("Entering EIBConnection.EIBGetBusmonitorPacket_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    self.buf = buf
    self.__complete = self:__EIBGetBusmonitorPacket_Complete();
    return 0
end

function EIBConnection.EIBGetBusmonitorPacket(self, buf)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBGetBusmonitorPacket()") end
    if self:EIBGetBusmonitorPacket_async (buf) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBGetGroup_Src_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBGetGroup_Src_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 39) or (#(self.data) < 6) then 
      self.errno = "ECONNRESET"
      return -1
    end
    if self.ptr5 ~= nil then
      self.ptr5.data =  bit.bor(  bit.lshift(self.data[2+1], 8) , (self.data[2+2]))
    end
    if self.ptr6 ~= nil then
      self.ptr6.data =  bit.bor(  bit.lshift(self.data[4+1], 8) , (self.data[4+2]))
    end
    self.buf.buffer = self.data:sub(6)
    return #(self.buf.buffer)

end

function EIBConnection.EIBGetGroup_Src_async(self, buf, src, dest)
  if DEBUG then print("Entering EIBConnection.EIBGetGroup_Src_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    self.buf = buf
    self.ptr5 = src
    self.ptr6 = dest
    self.__complete = self:__EIBGetGroup_Src_Complete();
    return 0
end

function EIBConnection.EIBGetGroup_Src(self, buf, src, dest)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBGetGroup_Src()") end
    if self:EIBGetGroup_Src_async (buf, src, dest) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBGetTPDU_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBGetTPDU_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 37) or (#(self.data) < 4) then 
      self.errno = "ECONNRESET"
      return -1
    end
    if self.ptr5 ~= nil then
      self.ptr5.data =  bit.bor(  bit.lshift(self.data[2+1], 8) , (self.data[2+2]))
    end
    self.buf.buffer = self.data:sub(4)
    return #(self.buf.buffer)

end

function EIBConnection.EIBGetTPDU_async(self, buf, src)
  if DEBUG then print("Entering EIBConnection.EIBGetTPDU_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    self.buf = buf
    self.ptr5 = src
    self.__complete = self:__EIBGetTPDU_Complete();
    return 0
end

function EIBConnection.EIBGetTPDU(self, buf, src)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBGetTPDU()") end
    if self:EIBGetTPDU_async (buf, src) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_Cache_Clear_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_Cache_Clear_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 114) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_Cache_Clear_async(self)
  if DEBUG then print("Entering EIBConnection.EIB_Cache_Clear_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    ibuf[1] = 0
    ibuf[2] = 114
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_Cache_Clear_Complete();
    return 0
end

function EIBConnection.EIB_Cache_Clear(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_Cache_Clear()") end
    if self:EIB_Cache_Clear_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_Cache_Disable_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_Cache_Disable_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 113) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_Cache_Disable_async(self)
  if DEBUG then print("Entering EIBConnection.EIB_Cache_Disable_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    ibuf[1] = 0
    ibuf[2] = 113
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_Cache_Disable_Complete();
    return 0
end

function EIBConnection.EIB_Cache_Disable(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_Cache_Disable()") end
    if self:EIB_Cache_Disable_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_Cache_Enable_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_Cache_Enable_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if  bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 1 then 
      self.errno = "EBUSY"
      return -1
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 112) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_Cache_Enable_async(self)
  if DEBUG then print("Entering EIBConnection.EIB_Cache_Enable_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    ibuf[1] = 0
    ibuf[2] = 112
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_Cache_Enable_Complete();
    return 0
end

function EIBConnection.EIB_Cache_Enable(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_Cache_Enable()") end
    if self:EIB_Cache_Enable_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_Cache_Read_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_Cache_Read_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 117) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    if  bit.bor(  bit.lshift(self.data[4+1], 8) , (self.data[4+2])) == 0 then 
      self.errno = "ENODEV"
      return -1
    end
    if #(self.data) <= 6 then 
      self.errno = "ENOENT"
      return -1
    end
    if self.ptr5 ~= nil then
      self.ptr5.data =  bit.bor(  bit.lshift(self.data[2+1], 8) , (self.data[2+2]))
    end
    self.buf.buffer = self.data:sub(6)
    return #(self.buf.buffer)

end

function EIBConnection.EIB_Cache_Read_async(self, dst, src, buf)
  if DEBUG then print("Entering EIBConnection.EIB_Cache_Read_async()") end
    ibuf = {}
    for i=1,4 do ibuf[i]="" end
    self.buf = buf
    self.ptr5 = src
    ibuf[3] = (bit.band(bit.rshift(dst,8), 0xff))
    ibuf[4] = (bit.band(dst, 0xff))
    ibuf[1] = 0
    ibuf[2] = 117
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_Cache_Read_Complete();
    return 0
end

function EIBConnection.EIB_Cache_Read(self, dst, src, buf)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_Cache_Read()") end
    if self:EIB_Cache_Read_async (dst, src, buf) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_Cache_Read_Sync_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_Cache_Read_Sync_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 116) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    if  bit.bor(  bit.lshift(self.data[4+1], 8) , (self.data[4+2])) == 0 then 
      self.errno = "ENODEV"
      return -1
    end
    if #(self.data) <= 6 then 
      self.errno = "ENOENT"
      return -1
    end
    if self.ptr5 ~= nil then
      self.ptr5.data =  bit.bor(  bit.lshift(self.data[2+1], 8) , (self.data[2+2]))
    end
    self.buf.buffer = self.data:sub(6)
    return #(self.buf.buffer)

end

function EIBConnection.EIB_Cache_Read_Sync_async(self, dst, src, buf, age)
  if DEBUG then print("Entering EIBConnection.EIB_Cache_Read_Sync_async()") end
    ibuf = {}
    for i=1,6 do ibuf[i]="" end
    self.buf = buf
    self.ptr5 = src
    ibuf[3] = (bit.band(bit.rshift(dst,8), 0xff))
    ibuf[4] = (bit.band(dst, 0xff))
    ibuf[5] = (bit.band(bit.rshift(age,8), 0xff))
    ibuf[6] = (bit.band(age, 0xff))
    ibuf[1] = 0
    ibuf[2] = 116
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_Cache_Read_Sync_Complete();
    return 0
end

function EIBConnection.EIB_Cache_Read_Sync(self, dst, src, buf, age)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_Cache_Read_Sync()") end
    if self:EIB_Cache_Read_Sync_async (dst, src, buf, age) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_Cache_Remove_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_Cache_Remove_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 115) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_Cache_Remove_async(self, dest)
  if DEBUG then print("Entering EIBConnection.EIB_Cache_Remove_async()") end
    ibuf = {}
    for i=1,4 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    ibuf[1] = 0
    ibuf[2] = 115
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_Cache_Remove_Complete();
    return 0
end

function EIBConnection.EIB_Cache_Remove(self, dest)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_Cache_Remove()") end
    if self:EIB_Cache_Remove_async (dest) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_Cache_LastUpdates_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_Cache_LastUpdates_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 118) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    if self.ptr4 ~= nil then
      self.ptr4.data =  bit.bor(  bit.lshift(self.data[2+1], 8) , (self.data[2+2]))
    end
    self.buf.buffer = self.data:sub(4)
    return #(self.buf.buffer)

end

function EIBConnection.EIB_Cache_LastUpdates_async(self, start, timeout, buf, ende)
  if DEBUG then print("Entering EIBConnection.EIB_Cache_LastUpdates_async()") end
    ibuf = {}
    for i=1,5 do ibuf[i]="" end
    self.buf = buf
    self.ptr4 = ende
    ibuf[3] = (bit.band(bit.rshift(start,8), 0xff))
    ibuf[4] = (bit.band(start, 0xff))
    ibuf[5] = (bit.band(timeout, 0xff))
    ibuf[1] = 0
    ibuf[2] = 118
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_Cache_LastUpdates_Complete();
    return 0
end

function EIBConnection.EIB_Cache_LastUpdates(self, start, timeout, buf, ende)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_Cache_LastUpdates()") end
    if self:EIB_Cache_LastUpdates_async (start, timeout, buf, ende) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_LoadImage_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_LoadImage_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 99) or (#(self.data) < 4) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return  bit.bor(  bit.lshift(self.data[2+1], 8) , (self.data[2+2]))

end

function EIBConnection.EIB_LoadImage_async(self, image)
  if DEBUG then print("Entering EIBConnection.EIB_LoadImage_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    if (#image < 0) then 
      self.errno = "EINVAL"
      return -1
    end
    self.sendlen = #image
    for i=1,#image do table.insert(ibuf, image[i]) end
    --ibuf = ibuf .. image
    ibuf[1] = 0
    ibuf[2] = 99
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_LoadImage_Complete();
    return 0
end

function EIBConnection.EIB_LoadImage(self, image)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_LoadImage()") end
    if self:EIB_LoadImage_async (image) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_Authorize_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_Authorize_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 87) or (#(self.data) < 3) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return self.data[2]

end

function EIBConnection.EIB_MC_Authorize_async(self, key)
  if DEBUG then print("Entering EIBConnection.EIB_MC_Authorize_async()") end
    ibuf = {}
    for i=1,6 do ibuf[i]="" end
    if #key ~= 4 then 
      self.errno = "EINVAL"
      return -1
    end
    for i=1,4 do ibuf[2+i] = key[i] end
    --UGLY HACK: was: ibuf[2..6] = key
    ibuf[1] = 0
    ibuf[2] = 87
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_Authorize_Complete();
    return 0
end

function EIBConnection.EIB_MC_Authorize(self, key)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_Authorize()") end
    if self:EIB_MC_Authorize_async (key) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_Connect_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_Connect_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 80) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_MC_Connect_async(self, dest)
  if DEBUG then print("Entering EIBConnection.EIB_MC_Connect_async()") end
    ibuf = {}
    for i=1,4 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    ibuf[1] = 0
    ibuf[2] = 80
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_Connect_Complete();
    return 0
end

function EIBConnection.EIB_MC_Connect(self, dest)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_Connect()") end
    if self:EIB_MC_Connect_async (dest) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_Individual_Open_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_Individual_Open_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 73) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_MC_Individual_Open_async(self, dest)
  if DEBUG then print("Entering EIBConnection.EIB_MC_Individual_Open_async()") end
    ibuf = {}
    for i=1,4 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    ibuf[1] = 0
    ibuf[2] = 73
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_Individual_Open_Complete();
    return 0
end

function EIBConnection.EIB_MC_Individual_Open(self, dest)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_Individual_Open()") end
    if self:EIB_MC_Individual_Open_async (dest) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_GetMaskVersion_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_GetMaskVersion_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 89) or (#(self.data) < 4) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return  bit.bor(  bit.lshift(self.data[2+1], 8) , (self.data[2+2]))

end

function EIBConnection.EIB_MC_GetMaskVersion_async(self)
  if DEBUG then print("Entering EIBConnection.EIB_MC_GetMaskVersion_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    ibuf[1] = 0
    ibuf[2] = 89
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_GetMaskVersion_Complete();
    return 0
end

function EIBConnection.EIB_MC_GetMaskVersion(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_GetMaskVersion()") end
    if self:EIB_MC_GetMaskVersion_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_GetPEIType_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_GetPEIType_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 85) or (#(self.data) < 4) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return  bit.bor(  bit.lshift(self.data[2+1], 8) , (self.data[2+2]))

end

function EIBConnection.EIB_MC_GetPEIType_async(self)
  if DEBUG then print("Entering EIBConnection.EIB_MC_GetPEIType_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    ibuf[1] = 0
    ibuf[2] = 85
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_GetPEIType_Complete();
    return 0
end

function EIBConnection.EIB_MC_GetPEIType(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_GetPEIType()") end
    if self:EIB_MC_GetPEIType_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_Progmode_Off_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_Progmode_Off_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 96) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_MC_Progmode_Off_async(self)
  if DEBUG then print("Entering EIBConnection.EIB_MC_Progmode_Off_async()") end
    ibuf = {}
    for i=1,3 do ibuf[i]="" end
    ibuf[3] = (bit.band(0, 0xff))
    ibuf[1] = 0
    ibuf[2] = 96
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_Progmode_Off_Complete();
    return 0
end

function EIBConnection.EIB_MC_Progmode_Off(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_Progmode_Off()") end
    if self:EIB_MC_Progmode_Off_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_Progmode_On_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_Progmode_On_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 96) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_MC_Progmode_On_async(self)
  if DEBUG then print("Entering EIBConnection.EIB_MC_Progmode_On_async()") end
    ibuf = {}
    for i=1,3 do ibuf[i]="" end
    ibuf[3] = (bit.band(1, 0xff))
    ibuf[1] = 0
    ibuf[2] = 96
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_Progmode_On_Complete();
    return 0
end

function EIBConnection.EIB_MC_Progmode_On(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_Progmode_On()") end
    if self:EIB_MC_Progmode_On_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_Progmode_Status_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_Progmode_Status_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 96) or (#(self.data) < 3) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return self.data[2]

end

function EIBConnection.EIB_MC_Progmode_Status_async(self)
  if DEBUG then print("Entering EIBConnection.EIB_MC_Progmode_Status_async()") end
    ibuf = {}
    for i=1,3 do ibuf[i]="" end
    ibuf[3] = (bit.band(3, 0xff))
    ibuf[1] = 0
    ibuf[2] = 96
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_Progmode_Status_Complete();
    return 0
end

function EIBConnection.EIB_MC_Progmode_Status(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_Progmode_Status()") end
    if self:EIB_MC_Progmode_Status_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_Progmode_Toggle_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_Progmode_Toggle_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 96) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_MC_Progmode_Toggle_async(self)
  if DEBUG then print("Entering EIBConnection.EIB_MC_Progmode_Toggle_async()") end
    ibuf = {}
    for i=1,3 do ibuf[i]="" end
    ibuf[3] = (bit.band(2, 0xff))
    ibuf[1] = 0
    ibuf[2] = 96
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_Progmode_Toggle_Complete();
    return 0
end

function EIBConnection.EIB_MC_Progmode_Toggle(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_Progmode_Toggle()") end
    if self:EIB_MC_Progmode_Toggle_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_PropertyDesc_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_PropertyDesc_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 97) or (#(self.data) < 6) then 
      self.errno = "ECONNRESET"
      return -1
    end
    if self.ptr2 ~= nil then
      self.ptr2.data = self.data[2]
    end
    if self.ptr4 ~= nil then
      self.ptr4.data =  bit.bor(  bit.lshift(self.data[3+1], 8) , (self.data[3+2]))
    end
    if self.ptr3 ~= nil then
      self.ptr3.data = self.data[5]
    end
    return 0

end

function EIBConnection.EIB_MC_PropertyDesc_async(self, obj, propertyno, proptype, max_nr_of_elem, access)
  if DEBUG then print("Entering EIBConnection.EIB_MC_PropertyDesc_async()") end
    ibuf = {}
    for i=1,4 do ibuf[i]="" end
    self.ptr2 = proptype
    self.ptr4 = max_nr_of_elem
    self.ptr3 = access
    ibuf[3] = (bit.band(obj, 0xff))
    ibuf[4] = (bit.band(propertyno, 0xff))
    ibuf[1] = 0
    ibuf[2] = 97
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_PropertyDesc_Complete();
    return 0
end

function EIBConnection.EIB_MC_PropertyDesc(self, obj, propertyno, proptype, max_nr_of_elem, access)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_PropertyDesc()") end
    if self:EIB_MC_PropertyDesc_async (obj, propertyno, proptype, max_nr_of_elem, access) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_PropertyRead_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_PropertyRead_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 83) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    self.buf.buffer = self.data:sub(2)
    return #(self.buf.buffer)

end

function EIBConnection.EIB_MC_PropertyRead_async(self, obj, propertyno, start, nr_of_elem, buf)
  if DEBUG then print("Entering EIBConnection.EIB_MC_PropertyRead_async()") end
    ibuf = {}
    for i=1,7 do ibuf[i]="" end
    self.buf = buf
    ibuf[3] = (bit.band(obj, 0xff))
    ibuf[4] = (bit.band(propertyno, 0xff))
    ibuf[5] = (bit.band(bit.rshift(start,8), 0xff))
    ibuf[6] = (bit.band(start, 0xff))
    ibuf[7] = (bit.band(nr_of_elem, 0xff))
    ibuf[1] = 0
    ibuf[2] = 83
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_PropertyRead_Complete();
    return 0
end

function EIBConnection.EIB_MC_PropertyRead(self, obj, propertyno, start, nr_of_elem, buf)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_PropertyRead()") end
    if self:EIB_MC_PropertyRead_async (obj, propertyno, start, nr_of_elem, buf) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_PropertyScan_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_PropertyScan_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 98) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    self.buf.buffer = self.data:sub(2)
    return #(self.buf.buffer)

end

function EIBConnection.EIB_MC_PropertyScan_async(self, buf)
  if DEBUG then print("Entering EIBConnection.EIB_MC_PropertyScan_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    self.buf = buf
    ibuf[1] = 0
    ibuf[2] = 98
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_PropertyScan_Complete();
    return 0
end

function EIBConnection.EIB_MC_PropertyScan(self, buf)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_PropertyScan()") end
    if self:EIB_MC_PropertyScan_async (buf) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_PropertyWrite_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_PropertyWrite_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 84) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    self.buf.buffer = self.data:sub(2)
    return #(self.buf.buffer)

end

function EIBConnection.EIB_MC_PropertyWrite_async(self, obj, propertyno, start, nr_of_elem, buf, res)
  if DEBUG then print("Entering EIBConnection.EIB_MC_PropertyWrite_async()") end
    ibuf = {}
    for i=1,7 do ibuf[i]="" end
    ibuf[3] = (bit.band(obj, 0xff))
    ibuf[4] = (bit.band(propertyno, 0xff))
    ibuf[5] = (bit.band(bit.rshift(start,8), 0xff))
    ibuf[6] = (bit.band(start, 0xff))
    ibuf[7] = (bit.band(nr_of_elem, 0xff))
    if (#buf < 0) then 
      self.errno = "EINVAL"
      return -1
    end
    self.sendlen = #buf
    for i=1,#buf do table.insert(ibuf, buf[i]) end
    --ibuf = ibuf .. buf
    self.buf = res
    ibuf[1] = 0
    ibuf[2] = 84
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_PropertyWrite_Complete();
    return 0
end

function EIBConnection.EIB_MC_PropertyWrite(self, obj, propertyno, start, nr_of_elem, buf, res)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_PropertyWrite()") end
    if self:EIB_MC_PropertyWrite_async (obj, propertyno, start, nr_of_elem, buf, res) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_ReadADC_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_ReadADC_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 86) or (#(self.data) < 4) then 
      self.errno = "ECONNRESET"
      return -1
    end
    if self.ptr1 ~= nil then
      self.ptr1.data =  bit.bor(  bit.lshift(self.data[2+1], 8) , (self.data[2+2]))
    end
    return 0

end

function EIBConnection.EIB_MC_ReadADC_async(self, channel, count, val)
  if DEBUG then print("Entering EIBConnection.EIB_MC_ReadADC_async()") end
    ibuf = {}
    for i=1,4 do ibuf[i]="" end
    self.ptr1 = val
    ibuf[3] = (bit.band(channel, 0xff))
    ibuf[4] = (bit.band(count, 0xff))
    ibuf[1] = 0
    ibuf[2] = 86
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_ReadADC_Complete();
    return 0
end

function EIBConnection.EIB_MC_ReadADC(self, channel, count, val)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_ReadADC()") end
    if self:EIB_MC_ReadADC_async (channel, count, val) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_Read_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_Read_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 81) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    self.buf.buffer = self.data:sub(2)
    return #(self.buf.buffer)

end

function EIBConnection.EIB_MC_Read_async(self, addr, buf_len, buf)
  if DEBUG then print("Entering EIBConnection.EIB_MC_Read_async()") end
    ibuf = {}
    for i=1,6 do ibuf[i]="" end
    self.buf = buf
    ibuf[3] = (bit.band(bit.rshift(addr,8), 0xff))
    ibuf[4] = (bit.band(addr, 0xff))
    ibuf[5] = (bit.band(bit.rshift(buf_len,8), 0xff))
    ibuf[6] = (bit.band(buf_len, 0xff))
    ibuf[1] = 0
    ibuf[2] = 81
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_Read_Complete();
    return 0
end

function EIBConnection.EIB_MC_Read(self, addr, buf_len, buf)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_Read()") end
    if self:EIB_MC_Read_async (addr, buf_len, buf) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_Restart_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_Restart_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 90) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_MC_Restart_async(self)
  if DEBUG then print("Entering EIBConnection.EIB_MC_Restart_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    ibuf[1] = 0
    ibuf[2] = 90
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_Restart_Complete();
    return 0
end

function EIBConnection.EIB_MC_Restart(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_Restart()") end
    if self:EIB_MC_Restart_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_SetKey_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_SetKey_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if  bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 2 then 
      self.errno = "EPERM"
      return -1
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 88) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_MC_SetKey_async(self, key, level)
  if DEBUG then print("Entering EIBConnection.EIB_MC_SetKey_async()") end
    ibuf = {}
    for i=1,7 do ibuf[i]="" end
    if #key ~= 4 then 
      self.errno = "EINVAL"
      return -1
    end
    for i=1,4 do ibuf[2+i] = key[i] end
    --UGLY HACK: was: ibuf[2..6] = key
    ibuf[7] = (bit.band(level, 0xff))
    ibuf[1] = 0
    ibuf[2] = 88
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_SetKey_Complete();
    return 0
end

function EIBConnection.EIB_MC_SetKey(self, key, level)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_SetKey()") end
    if self:EIB_MC_SetKey_async (key, level) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_Write_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_Write_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if  bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 68 then 
      self.errno = "EIO"
      return -1
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 82) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return self.sendlen

end

function EIBConnection.EIB_MC_Write_async(self, addr, buf)
  if DEBUG then print("Entering EIBConnection.EIB_MC_Write_async()") end
    ibuf = {}
    for i=1,6 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(addr,8), 0xff))
    ibuf[4] = (bit.band(addr, 0xff))
    ibuf[5] = (bit.band(bit.rshift("buf",8), 0xff))
    ibuf[6] = (bit.band("buf", 0xff))
    if (#buf < 0) then 
      self.errno = "EINVAL"
      return -1
    end
    self.sendlen = #buf
    for i=1,#buf do table.insert(ibuf, buf[i]) end
    --ibuf = ibuf .. buf
    ibuf[1] = 0
    ibuf[2] = 82
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_Write_Complete();
    return 0
end

function EIBConnection.EIB_MC_Write(self, addr, buf)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_Write()") end
    if self:EIB_MC_Write_async (addr, buf) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_MC_Write_Plain_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_MC_Write_Plain_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 91) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return self.sendlen

end

function EIBConnection.EIB_MC_Write_Plain_async(self, addr, buf)
  if DEBUG then print("Entering EIBConnection.EIB_MC_Write_Plain_async()") end
    ibuf = {}
    for i=1,6 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(addr,8), 0xff))
    ibuf[4] = (bit.band(addr, 0xff))
    ibuf[5] = (bit.band(bit.rshift("buf",8), 0xff))
    ibuf[6] = (bit.band("buf", 0xff))
    if (#buf < 0) then 
      self.errno = "EINVAL"
      return -1
    end
    self.sendlen = #buf
    for i=1,#buf do table.insert(ibuf, buf[i]) end
    --ibuf = ibuf .. buf
    ibuf[1] = 0
    ibuf[2] = 91
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_MC_Write_Plain_Complete();
    return 0
end

function EIBConnection.EIB_MC_Write_Plain(self, addr, buf)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_MC_Write_Plain()") end
    if self:EIB_MC_Write_Plain_async (addr, buf) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_M_GetMaskVersion_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_M_GetMaskVersion_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 49) or (#(self.data) < 4) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return  bit.bor(  bit.lshift(self.data[2+1], 8) , (self.data[2+2]))

end

function EIBConnection.EIB_M_GetMaskVersion_async(self, dest)
  if DEBUG then print("Entering EIBConnection.EIB_M_GetMaskVersion_async()") end
    ibuf = {}
    for i=1,4 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    ibuf[1] = 0
    ibuf[2] = 49
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_M_GetMaskVersion_Complete();
    return 0
end

function EIBConnection.EIB_M_GetMaskVersion(self, dest)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_M_GetMaskVersion()") end
    if self:EIB_M_GetMaskVersion_async (dest) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_M_Progmode_Off_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_M_Progmode_Off_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 48) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_M_Progmode_Off_async(self, dest)
  if DEBUG then print("Entering EIBConnection.EIB_M_Progmode_Off_async()") end
    ibuf = {}
    for i=1,5 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    ibuf[5] = (bit.band(0, 0xff))
    ibuf[1] = 0
    ibuf[2] = 48
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_M_Progmode_Off_Complete();
    return 0
end

function EIBConnection.EIB_M_Progmode_Off(self, dest)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_M_Progmode_Off()") end
    if self:EIB_M_Progmode_Off_async (dest) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_M_Progmode_On_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_M_Progmode_On_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 48) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_M_Progmode_On_async(self, dest)
  if DEBUG then print("Entering EIBConnection.EIB_M_Progmode_On_async()") end
    ibuf = {}
    for i=1,5 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    ibuf[5] = (bit.band(1, 0xff))
    ibuf[1] = 0
    ibuf[2] = 48
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_M_Progmode_On_Complete();
    return 0
end

function EIBConnection.EIB_M_Progmode_On(self, dest)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_M_Progmode_On()") end
    if self:EIB_M_Progmode_On_async (dest) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_M_Progmode_Status_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_M_Progmode_Status_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 48) or (#(self.data) < 3) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return self.data[2]

end

function EIBConnection.EIB_M_Progmode_Status_async(self, dest)
  if DEBUG then print("Entering EIBConnection.EIB_M_Progmode_Status_async()") end
    ibuf = {}
    for i=1,5 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    ibuf[5] = (bit.band(3, 0xff))
    ibuf[1] = 0
    ibuf[2] = 48
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_M_Progmode_Status_Complete();
    return 0
end

function EIBConnection.EIB_M_Progmode_Status(self, dest)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_M_Progmode_Status()") end
    if self:EIB_M_Progmode_Status_async (dest) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_M_Progmode_Toggle_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_M_Progmode_Toggle_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 48) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_M_Progmode_Toggle_async(self, dest)
  if DEBUG then print("Entering EIBConnection.EIB_M_Progmode_Toggle_async()") end
    ibuf = {}
    for i=1,5 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    ibuf[5] = (bit.band(2, 0xff))
    ibuf[1] = 0
    ibuf[2] = 48
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_M_Progmode_Toggle_Complete();
    return 0
end

function EIBConnection.EIB_M_Progmode_Toggle(self, dest)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_M_Progmode_Toggle()") end
    if self:EIB_M_Progmode_Toggle_async (dest) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_M_ReadIndividualAddresses_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_M_ReadIndividualAddresses_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 50) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    self.buf.buffer = self.data:sub(2)
    return #(self.buf.buffer)

end

function EIBConnection.EIB_M_ReadIndividualAddresses_async(self, buf)
  if DEBUG then print("Entering EIBConnection.EIB_M_ReadIndividualAddresses_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    self.buf = buf
    ibuf[1] = 0
    ibuf[2] = 50
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_M_ReadIndividualAddresses_Complete();
    return 0
end

function EIBConnection.EIB_M_ReadIndividualAddresses(self, buf)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_M_ReadIndividualAddresses()") end
    if self:EIB_M_ReadIndividualAddresses_async (buf) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIB_M_WriteIndividualAddress_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIB_M_WriteIndividualAddress_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if  bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 65 then 
      self.errno = "EADDRINUSE"
      return -1
    end
    if  bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 67 then 
      self.errno = "ETIMEDOUT"
      return -1
    end
    if  bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 66 then 
      self.errno = "EADDRNOTAVAIL"
      return -1
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 64) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIB_M_WriteIndividualAddress_async(self, dest)
  if DEBUG then print("Entering EIBConnection.EIB_M_WriteIndividualAddress_async()") end
    ibuf = {}
    for i=1,4 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    ibuf[1] = 0
    ibuf[2] = 64
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIB_M_WriteIndividualAddress_Complete();
    return 0
end

function EIBConnection.EIB_M_WriteIndividualAddress(self, dest)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIB_M_WriteIndividualAddress()") end
    if self:EIB_M_WriteIndividualAddress_async (dest) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBOpenBusmonitor_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBOpenBusmonitor_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if  bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 1 then 
      self.errno = "EBUSY"
      return -1
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 16) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIBOpenBusmonitor_async(self)
  if DEBUG then print("Entering EIBConnection.EIBOpenBusmonitor_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    ibuf[1] = 0
    ibuf[2] = 16
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIBOpenBusmonitor_Complete();
    return 0
end

function EIBConnection.EIBOpenBusmonitor(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBOpenBusmonitor()") end
    if self:EIBOpenBusmonitor_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBOpenBusmonitorText_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBOpenBusmonitorText_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if  bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 1 then 
      self.errno = "EBUSY"
      return -1
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 17) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIBOpenBusmonitorText_async(self)
  if DEBUG then print("Entering EIBConnection.EIBOpenBusmonitorText_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    ibuf[1] = 0
    ibuf[2] = 17
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIBOpenBusmonitorText_Complete();
    return 0
end

function EIBConnection.EIBOpenBusmonitorText(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBOpenBusmonitorText()") end
    if self:EIBOpenBusmonitorText_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBOpen_GroupSocket_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBOpen_GroupSocket_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 38) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIBOpen_GroupSocket_async(self, write_only)
  if DEBUG then print("Entering EIBConnection.EIBOpen_GroupSocket_async()") end
    ibuf = {}
    for i=1,5 do ibuf[i]="" end
    if write_only ~= 0  then 
      ibuf[5] = 0xff
    else
      ibuf[5] = 0x00
    end
    ibuf[1] = 0
    ibuf[2] = 38
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIBOpen_GroupSocket_Complete();
    return 0
end

function EIBConnection.EIBOpen_GroupSocket(self, write_only)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBOpen_GroupSocket()") end
    if self:EIBOpen_GroupSocket_async (write_only) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBOpenT_Broadcast_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBOpenT_Broadcast_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 35) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIBOpenT_Broadcast_async(self, write_only)
  if DEBUG then print("Entering EIBConnection.EIBOpenT_Broadcast_async()") end
    ibuf = {}
    for i=1,5 do ibuf[i]="" end
    if write_only ~= 0  then 
      ibuf[5] = 0xff
    else
      ibuf[5] = 0x00
    end
    ibuf[1] = 0
    ibuf[2] = 35
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIBOpenT_Broadcast_Complete();
    return 0
end

function EIBConnection.EIBOpenT_Broadcast(self, write_only)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBOpenT_Broadcast()") end
    if self:EIBOpenT_Broadcast_async (write_only) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBOpenT_Connection_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBOpenT_Connection_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 32) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIBOpenT_Connection_async(self, dest)
  if DEBUG then print("Entering EIBConnection.EIBOpenT_Connection_async()") end
    ibuf = {}
    for i=1,5 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    ibuf[1] = 0
    ibuf[2] = 32
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIBOpenT_Connection_Complete();
    return 0
end

function EIBConnection.EIBOpenT_Connection(self, dest)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBOpenT_Connection()") end
    if self:EIBOpenT_Connection_async (dest) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBOpenT_Group_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBOpenT_Group_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 34) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIBOpenT_Group_async(self, dest, write_only)
  if DEBUG then print("Entering EIBConnection.EIBOpenT_Group_async()") end
    ibuf = {}
    for i=1,5 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    if write_only ~= 0  then 
      ibuf[5] = 0xff
    else
      ibuf[5] = 0x00
    end
    ibuf[1] = 0
    ibuf[2] = 34
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIBOpenT_Group_Complete();
    return 0
end

function EIBConnection.EIBOpenT_Group(self, dest, write_only)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBOpenT_Group()") end
    if self:EIBOpenT_Group_async (dest, write_only) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBOpenT_Individual_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBOpenT_Individual_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 33) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIBOpenT_Individual_async(self, dest, write_only)
  if DEBUG then print("Entering EIBConnection.EIBOpenT_Individual_async()") end
    ibuf = {}
    for i=1,5 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    if write_only ~= 0  then 
      ibuf[5] = 0xff
    else
      ibuf[5] = 0x00
    end
    ibuf[1] = 0
    ibuf[2] = 33
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIBOpenT_Individual_Complete();
    return 0
end

function EIBConnection.EIBOpenT_Individual(self, dest, write_only)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBOpenT_Individual()") end
    if self:EIBOpenT_Individual_async (dest, write_only) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBOpenT_TPDU_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBOpenT_TPDU_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 36) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIBOpenT_TPDU_async(self, src)
  if DEBUG then print("Entering EIBConnection.EIBOpenT_TPDU_async()") end
    ibuf = {}
    for i=1,5 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(src,8), 0xff))
    ibuf[4] = (bit.band(src, 0xff))
    ibuf[1] = 0
    ibuf[2] = 36
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIBOpenT_TPDU_Complete();
    return 0
end

function EIBConnection.EIBOpenT_TPDU(self, src)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBOpenT_TPDU()") end
    if self:EIBOpenT_TPDU_async (src) == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBOpenVBusmonitor_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBOpenVBusmonitor_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if  bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 1 then 
      self.errno = "EBUSY"
      return -1
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 18) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIBOpenVBusmonitor_async(self)
  if DEBUG then print("Entering EIBConnection.EIBOpenVBusmonitor_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    ibuf[1] = 0
    ibuf[2] = 18
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIBOpenVBusmonitor_Complete();
    return 0
end

function EIBConnection.EIBOpenVBusmonitor(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBOpenVBusmonitor()") end
    if self:EIBOpenVBusmonitor_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBOpenVBusmonitorText_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBOpenVBusmonitorText_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if  bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 1 then 
      self.errno = "EBUSY"
      return -1
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 19) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIBOpenVBusmonitorText_async(self)
  if DEBUG then print("Entering EIBConnection.EIBOpenVBusmonitorText_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    ibuf[1] = 0
    ibuf[2] = 19
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIBOpenVBusmonitorText_Complete();
    return 0
end

function EIBConnection.EIBOpenVBusmonitorText(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBOpenVBusmonitorText()") end
    if self:EIBOpenVBusmonitorText_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.__EIBReset_Complete(self)
    if DEBUG then print("Entering EIBConnection.__EIBReset_Complete()") end
    self.__complete = nil;
    if EIBConnection.__EIB_GetRequest(self) == -1 then 
      return -1;
    end
    if ( bit.bor(  bit.lshift(self.data[0+1], 8) , (self.data[0+2])) ~= 4) or (#(self.data) < 2) then 
      self.errno = "ECONNRESET"
      return -1
    end
    return 0

end

function EIBConnection.EIBReset_async(self)
  if DEBUG then print("Entering EIBConnection.EIBReset_async()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    ibuf[1] = 0
    ibuf[2] = 4
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    self.__complete = self:__EIBReset_Complete();
    return 0
end

function EIBConnection.EIBReset(self)
  local ibuf
    if DEBUG then print("Entering EIBConnection.EIBReset()") end
    if self:EIBReset_async () == -1  then 
      return -1
    end
    return self:EIBComplete()
  end

function EIBConnection.EIBSendAPDU(self, data)
  local ibuf
  if DEBUG then print("Entering EIBConnection.EIBSendAPDU()") end
    ibuf = {}
    for i=1,2 do ibuf[i]="" end
    if (#data < 2) then 
      self.errno = "EINVAL"
      return -1
    end
    self.sendlen = #data
    for i=1,#data do table.insert(ibuf, data[i]) end
    --ibuf = ibuf .. data
    ibuf[1] = 0
    ibuf[2] = 37
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    return self.sendlen
end

function EIBConnection.EIBSendGroup(self, dest, data)
  local ibuf
  if DEBUG then print("Entering EIBConnection.EIBSendGroup()") end
    ibuf = {}
    for i=1,4 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    if (#data < 2) then 
      self.errno = "EINVAL"
      return -1
    end
    self.sendlen = #data
    for i=1,#data do table.insert(ibuf, data[i]) end
    --ibuf = ibuf .. data
    ibuf[1] = 0
    ibuf[2] = 39
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    return self.sendlen
end

function EIBConnection.EIBSendTPDU(self, dest, data)
  local ibuf
  if DEBUG then print("Entering EIBConnection.EIBSendTPDU()") end
    ibuf = {}
    for i=1,4 do ibuf[i]="" end
    ibuf[3] = (bit.band(bit.rshift(dest,8), 0xff))
    ibuf[4] = (bit.band(dest, 0xff))
    if (#data < 2) then 
      self.errno = "EINVAL"
      return -1
    end
    self.sendlen = #data
    for i=1,#data do table.insert(ibuf, data[i]) end
    --ibuf = ibuf .. data
    ibuf[1] = 0
    ibuf[2] = 37
    if self:__EIB_SendRequest(ibuf) == -1 then 
      return -1;
    end
    return self.sendlen
end

IMG_UNKNOWN_ERROR = 0
IMG_UNRECOG_FORMAT = 1
IMG_INVALID_FORMAT = 2
IMG_NO_BCUTYPE = 3
IMG_UNKNOWN_BCUTYPE = 4
IMG_NO_CODE = 5
IMG_NO_SIZE = 6
IMG_LODATA_OVERFLOW = 7
IMG_HIDATA_OVERFLOW = 8
IMG_TEXT_OVERFLOW = 9
IMG_NO_ADDRESS = 10
IMG_WRONG_SIZE = 11
IMG_IMAGE_LOADABLE = 12
IMG_NO_DEVICE_CONNECTION = 13
IMG_MASK_READ_FAILED = 14
IMG_WRONG_MASK_VERSION = 15
IMG_CLEAR_ERROR = 16
IMG_RESET_ADDR_TAB = 17
IMG_LOAD_HEADER = 18
IMG_LOAD_MAIN = 19
IMG_ZERO_RAM = 20
IMG_FINALIZE_ADDR_TAB = 21
IMG_PREPARE_RUN = 22
IMG_RESTART = 23
IMG_LOADED = 24
IMG_NO_START = 25
IMG_WRONG_ADDRTAB = 26
IMG_ADDRTAB_OVERFLOW = 27
IMG_OVERLAP_ASSOCTAB = 28
IMG_OVERLAP_TEXT = 29
IMG_NEGATIV_TEXT_SIZE = 30
IMG_OVERLAP_PARAM = 31
IMG_OVERLAP_EEPROM = 32
IMG_OBJTAB_OVERFLOW = 33
IMG_WRONG_LOADCTL = 34
IMG_UNLOAD_ADDR = 35
IMG_UNLOAD_ASSOC = 36
IMG_UNLOAD_PROG = 37
IMG_LOAD_ADDR = 38
IMG_WRITE_ADDR = 39
IMG_SET_ADDR = 40
IMG_FINISH_ADDR = 41
IMG_LOAD_ASSOC = 42
IMG_WRITE_ASSOC = 43
IMG_SET_ASSOC = 44
IMG_FINISH_ASSOC = 45
IMG_LOAD_PROG = 46
IMG_ALLOC_LORAM = 47
IMG_ALLOC_HIRAM = 48
IMG_ALLOC_INIT = 49
IMG_ALLOC_RO = 50
IMG_ALLOC_EEPROM = 51
IMG_ALLOC_PARAM = 52
IMG_SET_PROG = 53
IMG_SET_TASK_PTR = 54
IMG_SET_OBJ = 55
IMG_SET_TASK2 = 56
IMG_FINISH_PROC = 57
IMG_WRONG_CHECKLIM = 58
IMG_INVALID_KEY = 59
IMG_AUTHORIZATION_FAILED = 60
IMG_KEY_WRITE = 61
