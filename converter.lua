--[[
	Scripted by LumberUniverse
]]

local HttpService = game:GetService('HttpService')
local CollectionService = game:GetService('CollectionService')

local PropertiesAPI = {}

local HttpService = game:GetService('HttpService')
local Models = Instance.new("Folder")

local DumpURL = 'https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/API-Dump.json'
local RootClass = '<<<ROOT>>>'

local DefaultOverwrites = {
	Anchored = true,
	TopSurface = Enum.SurfaceType.Smooth,
	BottomSurface = Enum.SurfaceType.Smooth
}

local AlwaysSave = {
	'MeshId'
}

local PropertiesAPI = {
	Defaults = {},
	Properties = {}
}

--[[
	Functions
]]

local function IsDeprecated(Property : Table)
	if not Property.Tags then return end

	return table.find(Property.Tags, 'Deprecated') ~= nil
end

local function IsWriteable(Property : Table)
	return table.find(AlwaysSave, Property.Name) or Property.Security and (Property.Security == 'None' or Property.Security.Write == 'None') and (not Property.Tags or not table.find(Property.Tags, 'ReadOnly'))
end

function PropertiesAPI:GetDefaults(ClassName : String)
	assert(ClassName, 'No class name was given')

	if self.Defaults[ClassName] then return self.Defaults[ClassName] end

	local success, instance = pcall(function()
		return Instance.new(ClassName)
	end)

	if not success then error(instance) return {} end

	local defaults = {}
	local properties = self:GetProperties(ClassName)

	for i, property in pairs(properties)do
		pcall(function()
			defaults[property.Name] = (DefaultOverwrites[property.Name] ~= nil and DefaultOverwrites[property.Name]) or instance[property.Name]
		end)
	end

	table.sort(properties, function(a, b) return a.Name < b.Name end)

	self.Defaults[ClassName] = defaults

	instance:Destroy()

	return defaults
end

function PropertiesAPI:GetProperties(ClassName : String)
	assert(ClassName, 'No class name was given')

	if self.Properties[ClassName] then return self.Properties[ClassName] end

	local properties = {}

	for i, data in pairs(self.Dump.Classes)do
		if data.Name and data.Name == ClassName then
			for i, property in pairs(data.Members)do
				if not property.Name or not property.ValueType or not property.MemberType or property.MemberType ~= 'Property' or IsDeprecated(property) or not IsWriteable(property) then continue end

				table.insert(properties, property)
			end

			if data.Superclass and data.Superclass ~= RootClass then
				for i, property in pairs(self:GetProperties(data.Superclass) or {})do
					table.insert(properties, property)
				end
			end

			break
		end
	end

	table.sort(properties, function(a, b) return a.Name < b.Name end)

	self.Properties[ClassName] = properties

	return properties
end

PropertiesAPI.Dump = HttpService:JSONDecode(HttpService:GetAsync(DumpURL))

local Converter = {
	AssignGUIDs = {},
	Meshes = {},
	ModelsCache = {}
}

local DontSave = {
	'Parent',
	'BrickColor',
	'Orientation',
	'Position',
	'WorldPivot'
}

local DontSaveIf = {
	Rotation = {'CFrame'},
	WorldAxis = {'CFrame'},
	WorldPosition = {'CFrame'},
	WorldCFrame = {'CFrame'},
	WorldOrientation = {'CFrame'}
}

local ValueTypeRenames = {
	int = 'number'
}

local DataClasses = {
	CFrame = CFrame,
	Vector3 = Vector3,
	Vector2 = Vector2,
	UDim2 = UDim2,
	UDim = UDim,
	Color3 = Color3,
	BrickColor = BrickColor,
	NumberRange = NumberRange,
	Faces = {
		new = function(Values)
			return Faces.new(
				Values.Top and Enum.NormalId.Top,
				Values.Bottom and Enum.NormalId.Bottom,
				Values.Left and Enum.NormalId.Left,
				Values.Right and Enum.NormalId.Right,
				Values.Back and Enum.NormalId.Back,
				Values.Front and Enum.NormalId.Front
			)
		end,
	},
	NumberSequence = {
		new = function(...)
			local keypoints = {}
			local values = {...}
			
			for i, point in pairs(values)do
				table.insert(keypoints, NumberSequenceKeypoint.new(unpack(point)))
			end
			
			return NumberSequence.new(keypoints)
		end,
	},
	ColorSequence = {
		new = function(...)
			local keypoints = {}
			local values = {...}

			for i, point in pairs(values)do
				table.insert(keypoints, ColorSequenceKeypoint.new(point[1], Converter:ToUserData(point[2])))
			end

			return ColorSequence.new(keypoints)
		end,
	}
}

local function ShouldntSave(properties, property)
	if not DontSaveIf[property] or table.find(DontSave, property) then return table.find(DontSave, property) end
	
	for i, prop in pairs(DontSaveIf[property])do
		if properties[prop] then
			return true
		end
	end
end

function Converter:FindMeshPart(Mesh : String)
	if self.Meshes[Mesh] then return self.Meshes[Mesh] end
	
	for i, mesh in pairs(CollectionService:GetTagged('MeshPart'))do
		if mesh.MeshId:gsub('%D', '') == Mesh:gsub('%D', '') then
			self.Meshes[Mesh] = mesh
			
			return mesh
		end
	end
end

function Converter:ToValue(Parent : Instance, Value : Any)
	local Type = typeof(Value)
	local Data
	
	if (Type == 'Instance') and (Value:IsDescendantOf(Parent) or Value == Parent) then
		Data = Value:GetAttribute('GUID')
		--Data.Value = self:ConvertToTable(Value)
	elseif Type == 'CFrame' then
		Data = {Value:GetComponents()}
	elseif Type == 'Vector3' or Type == 'Vector2' then
		Data = {Value.X, Value.Y, Type == 'Vector3' and Value.Z}
	elseif Type == 'UDim2' then
		Data = {Value.X.Scale, Value.X.Offset, Value.Y.Scale, Value.Y.Offset}
	elseif Type == 'UDim' then
		Data = {Value.X, Value.Y}
	elseif (Type == 'ColorSequence') or (Type == 'NumberSequence') then
		Data = {}
		
		for i, keypoint in pairs(Value.Keypoints)do
			local value = self:ToValue(Parent, keypoint.Value)
			table.insert(Data.Value, {keypoint.Time, value, (Type == 'NumberSequence') and keypoint.Envelope})
		end
	elseif Type == 'Color3' or Type == 'BrickColor' then
		Data = {Value.r, Value.g, Value.b}
	elseif Type == 'Faces' then
		Data = {Value.Top, Value.Bottom, Value.Left, Value.Right, Value.Back, Value.Front}
	elseif Type == 'NumberRange' then
		Data = {Value.Min, Value.Max}
	elseif Type == 'EnumItem' then
		Data = Value.Value
	else
		Data = Value
	end
	
	return Data
end

function Converter:ToUserData(ClassName : String, Property : String, Value : Any)
	local properties = PropertiesAPI:GetProperties(ClassName)
	
	for i, property in pairs(properties)do
		if (property.Name ~= Property) or not property.ValueType or not property.ValueType.Name then continue end
		
		local valueType = property.ValueType.Name
		
		if ValueTypeRenames[valueType] then
			valueType = ValueTypeRenames[valueType]
		end
		
		if valueType then
			local DataType = DataClasses[valueType]
			
			if DataType then
				return DataType.new(unpack(Value))
			elseif valueType == 'EnumItem' then
				return Value
			elseif valueType == 'Instance' then
				return self:ConvertToInstance(Value)
			else
				return Value
			end
		else
			return Value
		end
	end
end

function Converter:ConvertToTable(Object : Instance, Parent : Instance, IncludeDescendants : Boolean)
	assert(Object, 'No object was passed through')
	
	if not Parent then Parent = Object end
	if not IncludeDescendants then IncludeDescendants = false end
	
	local model = self:GetModel(Object:GetAttribute('ModelID'))
	local properties = PropertiesAPI:GetProperties(Object.ClassName)
	local defaults = PropertiesAPI:GetDefaults(Object.ClassName)
	local data = {
		ClassName = (model and 'ModelStore') or Object.ClassName,
		ID = Object:GetAttribute('GUID'),
		ModelID = model and Object:GetAttribute('ModelID')
	}
	
	if Object:IsA('Script') or ((Object:IsA('Model') or Object:IsA('Folder')) and #Object:GetChildren() <= 0) then
		return
	end
	
	if model then
		data.CFrame = self:ToValue(Object, Object:GetPivot())
	else
		for i, property in pairs(properties)do
			property = property.Name
			if (defaults[property] ~= nil and Object[property] == defaults[property]) or ShouldntSave(data, property) then continue end
			
			pcall(function()
				data[property] = self:ToValue(Parent, Object[property])
			end)
		end
		
		if IncludeDescendants then
			data.Children = {}
			
			for i, child in pairs(Object:GetChildren())do
				local tab = self:ConvertToTable(child, Parent, IncludeDescendants)
				table.insert(data.Children, tab)
			end

			if #data.Children <= 0 then
				data.Children = nil
			end
		end
	end
	
	return data
end

function Converter:ConvertToSaveable(Object : Instance, IncludeDescendants : Boolean)
	for i, descendant in pairs({Object, unpack(Object:GetDescendants())})do
		descendant:SetAttribute('GUID', descendant:GetAttribute('GUID') or HttpService:GenerateGUID())
	end
	
	local data = self:ConvertToTable(Object, nil, IncludeDescendants)
	
	return HttpService:JSONDecode(HttpService:JSONEncode(data))
end

function Converter:GetModel(ID : String)
	if self.ModelsCache[ID] then return self.ModelsCache[ID] end
	
	for i, model in pairs(Models:GetChildren())do
		if model:GetAttribute('ModelID') == ID then
			self.ModelsCache[ID] = model
			
			return model
		end
	end
end

function Converter:ConvertToInstance(Data : Table)
	if not Data then return end
	
	local success, instance = pcall(function()
		return Instance.new(Data.ClassName)
	end)
	local needsToBeAssigned = {}

	if success then
		if Data.ClassName == 'MeshPart' and Data.MeshId and #Data.MeshId > 0 then
			local mesh = Converter:FindMeshPart(Data.MeshId)

			if mesh then
				instance:ApplyMesh(mesh)
			end
		end

		for property, value in pairs(Data)do
			if property == 'ClassName' or property == 'ID' then continue end

			if property == 'Children' then
				for i, child in pairs(value)do
					self:ConvertToInstance(child).Parent = instance
				end

				continue
			elseif type(value) == 'table' and value.Type == 'Instance' then
				task.spawn(function()
					repeat
						task.wait()
					until self.AssignGUIDs[value.Value]

					instance[property] = self.AssignGUIDs[value.Value]
				end)

				continue
			end

			pcall(function()
				instance[property] = self:ToUserData(Data.ClassName, property, value)
			end)
		end
	elseif self:GetModel(Data.ModelID) then
		instance = self:GetModel(Data.ModelID):Clone()
		instance:PivotTo(DataClasses.CFrame.new(unpack(Data.CFrame)))
	end
	
	self.AssignGUIDs[Data.ID] = instance
	
	return instance
end

for i, model in pairs(Models:GetChildren())do
	model:SetAttribute('ModelID', model:GetAttribute('ModelID') or HttpService:GenerateGUID())
end

for i, descendant in pairs(game:GetDescendants())do
	if descendant:IsA('MeshPart') then
		CollectionService:AddTag(descendant, 'MeshPart')
	end
end

return Converter
