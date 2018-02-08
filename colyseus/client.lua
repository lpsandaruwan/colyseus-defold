local Connection = require('colyseus.connection')
local Room = require('colyseus.room')
local protocol = require('colyseus.protocol')
local EventEmitter = require('colyseus.events').EventEmitter
local msgpack = require('colyseus.messagepack.MessagePack')

--
-- Utility functions
--
local colyseus_id_file = sys.get_save_file("colyseus", "colyseusid")
function get_colyseus_id ()
  local data = sys.load(colyseus_id_file)
  -- if not next(my_table) then
  -- end
  return data[1] or ""
end

function set_colyseus_id(colyseus_id)
  local data = {}
  table.insert(data, colyseus_id)
  if not sys.save(colyseus_id_file, data) then
    print("colyseus.client: set_colyseus_id couldn't set colyseus_id locally.")
  end
end

Client = {}
Client.__index = Client

function Client.new (endpoint)
  local instance = EventEmitter:new({
    id = nil ,
    roomStates = {}, -- object
    rooms = {}, -- object
    connectingRooms = {}, -- object
    joinRequestId = 0, -- number
  })
  setmetatable(instance, Client)
  instance:init(endpoint)
  return instance
end

function Client:init(endpoint)
  self.hostname = endpoint
  self.connection = Connection.new(self.hostname .. "/?colyseusid=" .. get_colyseus_id())

  self.connection:on("message", function(message)
    self:on_message(message)
  end)

  self.connection:on("close", function(message)
    self:emit("close", message)
  end)

  self.connection:on("error", function(message)
    self:emit("error", message)
  end)
end

function Client:loop()
  self.connection:loop()

  for k, room in pairs(self.rooms) do
    room:loop()
  end
end

function Client:close()
  self.connection:close()
end

function Client:join(...)
  local args = {...}

  local roomName = args[1]
  local options = args[2] or {}

  -- if not options then
  --   options = {}
  -- end

  self.joinRequestId = self.joinRequestId + 1
  options.requestId = self.joinRequestId;

  local room = Room.create(roomName);

  -- remove references on leaving
  room:on("leave", function()
    self.rooms[room.id] = nil
    self.connectingRooms[options.requestId] = nil
  end)

  self.connectingRooms[options.requestId] = room

  self.connection:send({ protocol.JOIN_ROOM, roomName, options });

  return self.connectingRooms[options.requestId]
end

function Client:on_message(msg)
  local message = msgpack.unpack( msg )

  if type(message[1]) == "number" then
    local roomId = message[2]

    if message[1] == protocol.USER_ID then
      set_colyseus_id(message[2])

      self.id = message[2]
      self:emit('open')

    elseif (message[1] == protocol.JOIN_ROOM) then
      local requestId = message[3]
      local room = self.connectingRooms[requestId]

      if not room then
        print("colyseus.client: client left room before receiving session id.")
        return
      end

      room.id = roomId;
      room:connect( Connection.new(self.hostname .. "/" .. room.id .. "?colyseusid=" .. self.id) );

      self.rooms[room.id] = room
      self.connectingRooms[ requestId ] = nil;

    elseif (message[1] == protocol.JOIN_ERROR) then
      self:emit("error", message[3])
      table.remove(self.rooms, roomId)

    else
      self:emit('message', message)

    end
  end
end

return Client
