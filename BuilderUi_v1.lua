local function isList(arrobj)
	local index = 1
	for i in pairs(arrobj) do
		if i ~= index then
			return false
		end
		index += 1
	end
	return true
end

local function getlength(obj)
    local index = 0
    table.foreach(obj, function() index += 1 end)
    return index
end

local signal = {}
signal.__index = signal

function signal.new()
    return setmetatable({Callbacks={},OnceCallbacks={}},signal)
end

function signal:Wait()
    local output = nil
    table.insert(self.OnceCallbacks,function(...)
        output = ...
    end)
    while task.wait() do
        if output then
            break
        end
    end
    return output
end

function signal:Once(callback)
    table.insert(self.OnceCallbacks,callback)
end

function signal:Connect(callback)
    table.insert(self.Callbacks,callback)
end

function signal:Disconnect()
    self.Callbacks = nil
    self = nil
end

function signal:Fire(...)
    local args = ...
    for i,v in pairs(self.Callbacks) do
        spawn(function()
            v(args)
        end)
    end
    for i,v in pairs(self.OnceCallbacks) do
        spawn(function()
            v(args)
        end)
    end
    self.OnceCallbacks = {}
end

local Socket = {}
Socket.__index = Socket

local function onclose_callback(SSocket, port)
    spawn(function()
        print("connection closed, trying to reconnect")

        local tries = 0
        while tries <= 10 do

            local success, newconnection = pcall(function() return WebSocket.connect("ws://localhost:"..port) end)
            if success then
                local sucessfuly, ping = pcall(function()  
                    local successfully_pinged = false
                    local start = tick()
                    newconnection.OnMessage:Connect(function(message)
                        if message == "PONG!" then
                            successfully_pinged = true
                        end
                    end)
                
                    newconnection:Send("ping") 

                    repeat
                        task.wait()
                    until successfully_pinged or tick() - start > 3

                    return successfully_pinged
                end)
                if sucessfuly and ping then
                    SSocket.socket = newconnection
                    SSocket.socket.OnMessage:Connect(function(message) SSocket.OnMessage:Fire(message) end)
                    SSocket.socket.OnClose:Connect(function()
                        onclose_callback(SSocket, port)
                    end)
                    print('reconnect successful')
                    break
                end
            end
            tries += 1
            wait(3)
        end
        if tries > 10 then
            print("reconnect unsuccessful")
        end
    end)
end

function Socket.new(port)
    local NewWebSocket = {}
    local waiting = false
    while true do
        local sucess, connection = pcall(function() return WebSocket.connect("ws://localhost:"..port) end)
        
        if sucess then
            local successfuly, ping = pcall(function()
                local successfully_pinged = false
                local start = tick()
                connection.OnMessage:Connect(function(message)
                    if message == "PONG!" then
                        successfully_pinged = true
                    end
                end)
            
                connection:Send("ping") 

                repeat
                    task.wait()
                until successfully_pinged or tick() - start > 5

                return successfully_pinged
            end)
            if successfuly and ping then
                NewWebSocket.socket = connection
                NewWebSocket.OnMessage = signal.new()

                NewWebSocket.socket.OnMessage:Connect(function(message) NewWebSocket.OnMessage:Fire(message) end)
                NewWebSocket.socket.OnClose:Connect(function()
                    onclose_callback(NewWebSocket, port)
                end)
                return setmetatable(NewWebSocket, Socket)
            else
                if not waiting then
                    print("waiting for server")
                    waiting = true
                end
            end
        end
    end
end

function Socket:Get(message)
    self.socket:Send(message)
    return self.OnMessage:Wait()
end

function Socket:Send(message)
    self.socket:Send(message)
end

local function GetImageSize(socket,image_name)
    local size = socket:Get("get_size:"..image_name)
    local size_dict = string.split(size,",")
    return {X = tonumber(size_dict[1]),Y = tonumber(size_dict[2])}
end

local function GetPixel(socket,image,x,y)
    return loadstring("return "+socket:Get(string.format("get_pixel:%s:%s:%s",image,x,y)))()
end

local blocks = game.Workspace.Blocks:FindFirstChild(game.Players.LocalPlayer.Name)
local information = {}
local colors = {}

local _building_tool = nil

local function GetBuildingTool()
    if not _building_tool or not _building_tool.Parent then
        _building_tool = game:GetService("Players").LocalPlayer.Backpack:FindFirstChild("BuildingTool") or game:GetService("Players").LocalPlayer.Character:FindFirstChild("BuildingTool")
    end
    return _building_tool
end

local function ToggleBuildingUI(enabled)
    game.Players.LocalPlayer.PlayerGui.BuildGui.Enabled = enabled
end

local function Build(block, pos, anchored)
    local tool = GetBuildingTool()
    if tool.Parent.Name == "Backpack" then
        tool.Parent = game.Players.LocalPlayer.Character
    end
    tool.RF:InvokeServer(block, game.Players.LocalPlayer.Data[block].Value, nil, CFrame.new(), anchored, pos, false)
end

local function CreateDot(Block,main_cf,str,size,compression,index)
    --local block_found = false
    local x,y,r,g,b = unpack(str:split(":"))
    local Place_Pos = main_cf*CFrame.new(0,0,-2*index)
    local Resize_Pos = main_cf*CFrame.new(size/compression*x,0,size/compression*y)
    local connection = blocks.ChildAdded:Connect(function(block)
        if block:WaitForChild("PPart",10) and (block.PPart.Position-Place_Pos.Position).Magnitude < 0.001 then
            --block_found = true
            table.insert(information,{Block=block,Position=Resize_Pos,Size=Vector3.new(size,size,size)})
            table.insert(colors,{block,Color3.fromRGB(r,g,b)})
        end
    end)

    Build(Block, Place_Pos, true)

    spawn(function()
        wait(3)
        connection:Disconnect()
        
        -- if not block_found then
        --     warn("BLOCK NOT FOUND")
        --     --CreateDot(Block, main_cf, str, size, compression)
        -- end
    end)
end

local function CreateDotNewColorLess(Block,main_cf,str,size,compression,index, data_arr, retry)
    local y_offset = retry*2
    local x,y,r,g,b = unpack(str:split(":"))
    local Place_Pos = main_cf*CFrame.new(0,y_offset,-2*index)
    local Resize_Pos = main_cf*CFrame.new(size/compression*x,0,size/compression*y)
    local found = false
    local connection = blocks.ChildAdded:Connect(function(block)
        if block:WaitForChild("PPart",10) and (block.PPart.Position-Place_Pos.Position).Magnitude < 0.001 then
            if retry > 0 then
                print('Brick renewed')
            end
            found = true
            table.insert(data_arr,{Block = block, Position=Resize_Pos, Size=Vector3.new(size,size,size)})
        end
    end)
    Build(Block, Place_Pos, true)
    spawn(function()
        wait(3)
        connection:Disconnect()
        if not found then
            CreateDotNewColorLess(Block, main_cf, str, size, compression, index, data_arr, retry+1)
        end
    end)
end

local function ResizeDot(Block,Size,Pos)
    while Block.PPart.Size ~= Size and wait(3) do
        game:GetService("Players").LocalPlayer.Backpack.ScalingTool.RF:InvokeServer(Block,Size,Pos)
    end
end

local function GetBlockCost(width,height,resize)
    return (math.ceil((width/resize))*math.ceil((height/resize)))
end

local function GetFiles(socket)
    return socket:Get("get_files"):split(",")
end
local image_extensions = {".jpeg", ".png", ".jpg"}

local function isSameColor(str1, str2)
    local _, __, r1, g1, b1 = unpack(str1:split(":"))
    local _, __, r2, g2, b2 = unpack(str2:split(":"))
    r1 = tonumber(r1)
    r2 = tonumber(r2)
    g1 = tonumber(g1)
    g2 = tonumber(g2)
    b1 = tonumber(b1)
    b2 = tonumber(b2)
    if r1==r2 and g1==g2 and b1==b2 then
        return true
    else
        return false
    end
end

local function IsFileAnImage(path)
    for index, extension in image_extensions do
        if string.find(path, extension) then
            return true
        end
    end
    return false
end

local sock = Socket.new(8000)

local function get_filesize(filename)
    local protocol = if IsFileAnImage(filename) then "get_size:" else "get_video_size:"
    return sock:Get(protocol .. filename):split(",")
end



local filename = ""
local building = false
local layout_style = "Vertical"
local block_name = "PlasticBlock"
local dot_size = 1
local resize = 2
local YOffset = 7
local preview = false
local looped = true
local frame_delay = .1

local previewpart = Instance.new("Part")
previewpart.Anchored = true
previewpart.Parent = workspace
previewpart.Transparency = 1
previewpart.Color = Color3.fromRGB(50,255,50)

local library = loadstring(game:HttpGet("https://pastebin.com/raw/tqKTJQAA", true))()
local ImageBuilder = library:CreateWindow('Image Builder')

local files = GetFiles(sock)
filename = files[1]

local image_size = get_filesize(filename)
local Width = tonumber(image_size[1])
local Height = tonumber(image_size[2])


ImageBuilder:Dropdown('Image File', {list=GetFiles(sock)}, function(file_name) 
    filename = file_name
    image_size = get_filesize(filename)
    Width = tonumber(image_size[1])
    Height = tonumber(image_size[2])
end)

ImageBuilder:Dropdown('Building Block', {list={"PlasticBlock","TitaniumBlock","MetalBlock","ObsidianBlock"}}, function(block) block_name = block end)
ImageBuilder:Dropdown('Layout Style', {list={"Vertical","Horizontal"}}, function(layout) layout_style = layout end)
ImageBuilder:Slider('Block Size', {precise=false, default=10, min=1, max=20}, function(value) dot_size = value/10 end)
ImageBuilder:Slider('Compression', {precise=false, default=1, min=1, max=50}, function(value) resize = value end)
ImageBuilder:Slider('Frame Delay', {precise=false, default=10, min=1, max=100}, function(value) frame_delay = value/200 end)
ImageBuilder:Slider('Y Axis Offset', {precise=false, default=7, min=1, max=80}, function(value) YOffset = value end)
ImageBuilder:Toggle("Preview Size", {}, function(value) preview = value; if value then previewpart.Transparency = 0.7 else previewpart.Transparency = 1 end end)
ImageBuilder:Toggle("Looped", {}, function(value) looped = value end)
ImageBuilder:Button("Start", function()
    if not building then
        if string.find(filename, ".png") or string.find(filename, ".jpeg") or string.find(filename, ".jpg")  then
            local blocks_value = game.Players.LocalPlayer.Data:FindFirstChild(block_name).Value
            local image_size = get_filesize(filename)
            local Width = tonumber(image_size[1])
            local Height = tonumber(image_size[2])
            if blocks_value >= GetBlockCost(Width,Height,resize) then
                building = true

                local start = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame*CFrame.new(0,((Height/resize)*dot_size)+YOffset,0)*CFrame.Angles(math.rad(90), 0, 0)
                local ended = false

                local pixels_arr = {}
                information = {}
                colors = {}

                sock.OnMessage:Connect(function(message)
                    if message ~= "stream_end" then
                        local pixels = message:split(",")
                        for i,v in pairs(pixels) do
                            if v ~= "" then
                                table.insert(pixels_arr,v)
                            end
                        end
                    else
                        ended = true
                    end
                end)

                sock:Send("stream_image:"..filename..":"..resize)

                repeat wait() until ended
                
                ToggleBuildingUI(false)
                GetBuildingTool().Parent = game.Players.LocalPlayer.Character

                for i,v in pairs(pixels_arr) do
                    if building then
                        spawn(function()
                            CreateDot(block_name,start,v,dot_size,resize,i)     
                        end)
                    else
                        return
                    end
                    task.wait(0.001)
                end

                wait(3)
                GetBuildingTool().Parent = game.Players.LocalPlayer.Backpack
                ToggleBuildingUI(true)

                for i,v in pairs(information) do
                    if building then
                        spawn(function()
                            ResizeDot(v.Block,v.Size,v.Position)
                        end)
                        task.wait(0.001)
                    else
                        return
                    end
                end

                wait(3)

                if building then
                    game:GetService("Players").LocalPlayer.Backpack.PaintingTool.RF:InvokeServer(colors)
                end

                building = false
            else
                print("You dont have enough blocks")
            end
        else
            local blocks_value = game.Players.LocalPlayer.Data:FindFirstChild(block_name).Value
            local video_size = get_filesize(filename)
            local Width = tonumber(video_size[1])
            local Height = tonumber(video_size[2])
            if blocks_value > GetBlockCost(Width, Height, resize) then
                building = true
                local ended = false
                local frames_arr = {}
                local bricks_arr = {}
                local start = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame*CFrame.new(0,((Height/resize)*dot_size)+YOffset,0)*CFrame.Angles(math.rad(90), 0, 0)
                
                sock.OnMessage:Connect(function(message)
                    if message ~= "stream_end" then
                        local pixels = message:split(",")
                        local frame_pixels = {}
                        for _,v in pairs(pixels) do
                            if v ~= "" then
                                table.insert(frame_pixels,v)
                            end
                        end
                        table.insert(frames_arr, frame_pixels)
                    else
                        ended = true
                    end
                end)

                sock:Send("stream_video:"..filename..":"..resize)
                
                repeat wait() until ended

                ToggleBuildingUI(false)
                GetBuildingTool().Parent = game.Players.LocalPlayer.Character

                for i,v in pairs(frames_arr[1]) do
                    if building then
                        spawn(function()
                            CreateDotNewColorLess(block_name, start, v, dot_size, resize, i, bricks_arr, 0)     
                        end)
                    else
                        return
                    end
                    task.wait(0.001)
                end

                wait(3)
                
                GetBuildingTool().Parent = game.Players.LocalPlayer.Backpack
                ToggleBuildingUI(true)

                for i,v in pairs(bricks_arr) do
                    if building then
                        spawn(function()
                            ResizeDot(v.Block,v.Size,v.Position)
                        end)
                        task.wait(0.001)
                    else
                        return
                    end
                end

                wait(3)
                
                while building do
                    local last_frame = nil
                    for frame_number, frame in pairs(frames_arr) do
                        
                        if building then
                            local colored_blocks = {}
                            
                            for i=1, getlength(frame) do
                                if not last_frame or (last_frame and not isSameColor(frame[i], last_frame[i])) then 
                                    local pixel_data = frame[i]
                                    local block_data = bricks_arr[i]
                                    local _, _, r, g, b = unpack(pixel_data:split(":"))
                                    table.insert(colored_blocks, {block_data["Block"], Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b))})
                                end
                            end
                            last_frame = frame
                            spawn(function()
                                game:GetService("Players").LocalPlayer.Backpack.PaintingTool.RF:InvokeServer(colored_blocks)
                            end)
                            wait(frame_delay)
                        end
                    end
                    if not looped then
                        break
                    end
                end
                building = false
            end
        end
    else
        building = false
    end
end)

spawn(function()
    while wait() do
        if preview and not building then
            previewpart.Size = Vector3.new(dot_size/resize*Width,dot_size,dot_size/resize*Height)
            previewpart.CFrame = game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame*CFrame.new(previewpart.Size.X/2,((Height/resize)*dot_size)/2+YOffset,0)*CFrame.Angles(math.rad(90), 0, 0)
        end
    end
end)
