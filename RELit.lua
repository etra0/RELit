--//////////////////////////////////////////////////////////////////////////////////////////////
--MIT License
--Copyright (c) 2022 Frans 'Otis_Inf' Bouma & Nicolás 'originalnicodr' Uriel Navall 
--
--Permission is hereby granted, free of charge, to any person obtaining a copy
--of this software and associated documentation files (the "Software"), to deal
--in the Software without restriction, including without limitation the rights
--to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--copies of the Software, and to permit persons to whom the Software is
--furnished to do so, subject to the following conditions:
--
--The above copyright notice and this permission notice shall be included in all
--copies or substantial portions of the Software.
--
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--SOFTWARE.
--//////////////////////////////////////////////////////////////////////////////////////////////
-- Changelog
-- v1.0		- First release
--//////////////////////////////////////////////////////////////////////////////////////////////

local relitVersion = "1.0"

local lightsTable = {}
local lightCounter = 0
local gameName = reframework:get_game_name()

function create_gameobj(name, component_names)
    local newGameobj = sdk.find_type_definition("via.GameObject"):get_method("create(System.String)"):call(nil, name)
    if newGameobj and newGameobj:add_ref() and newGameobj:call(".ctor") then
        for i, compName in ipairs(component_names or {}) do 
            local td = sdk.find_type_definition(compName)
            local newComponent = td and newGameobj:call("createComponent(System.Type)", td:get_runtime_type())
            if newComponent and newComponent:add_ref() then 
                newComponent:call(".ctor()")
            end
        end
        return newGameobj
    end
end

local function lua_find_component(gameobj, component_name)
	local out = gameobj:call("getComponent(System.Type)", sdk.typeof(component_name))
	if out then return out end
	local components = gameobj:call("get_Components")
	if tostring(components):find("SystemArray") then
		components = components:get_elements()
		for i, component in ipairs(components) do 
			if component:call("ToString") == component_name then 
				return component
			end
		end
	end
end

function dump(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dump(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
end
 
local function write_vec34(managedObject, offset, vector, doVec3)
	if sdk.is_managed_object(managedObject) then 
		managedObject:write_float(offset, vector.x)
		managedObject:write_float(offset + 4, vector.y)
		managedObject:write_float(offset + 8, vector.z)
		if not doVec3 and vector.w then managedObject:write_float(offset + 12, vector.w) end
	end
end

local function write_mat4(managedObject, offset, mat4)
	if sdk.is_managed_object(managedObject) then 
		write_vec34(managedObject, offset, 	 mat4[0])
		write_vec34(managedObject, offset + 16, mat4[1])
		write_vec34(managedObject, offset + 32, mat4[2])
		write_vec34(managedObject, offset + 48, mat4[3])
	end
end

local function move_light_to_camera(light)
    local lightTransform = light:call("get_Transform")
    local camera = sdk.get_primary_camera()
	local cameraObject = camera:call("get_GameObject")
	local cameraTransform = cameraObject:call("get_Transform")
	lightTransform:set_position(cameraTransform:get_position())
	lightTransform:set_rotation(cameraTransform:get_rotation())
	-- write matrix directly. Matrix is at offset 0x80
	write_mat4(lightTransform, 0x80, cameraTransform:call("get_WorldMatrix"))
end

local function ternary(cond, T, F)
	if cond then return T else return F end
end

local function add_new_light(lTable, createSpotLight, lightNo)
	local componentToCreate = ternary(createSpotLight, "via.render.SpotLight", "via.render.PointLight")
    local lightGameObject = create_gameobj(ternary(createSpotLight, "Spotlight ", "Pointlight ")..tostring(lightNo), {componentToCreate})
	local lightComponent = lua_find_component(lightGameObject, componentToCreate)
	
    lightComponent:call("set_Enabled", true)
    lightComponent:call("set_Color", Vector3f.new(1, 1, 1))
    lightComponent:call("set_Intensity", 1000.0)
	lightComponent:call("set_ImportantLevel", 0)
	lightComponent:call("set_BlackBodyRadiation", false)
	lightComponent:call("set_UsingSameIntensity", false)
	lightComponent:call("set_BackGroundShadowEnable", false)
    lightComponent:call("set_ShadowEnable", true)
	lightComponent:call("set_ShadowBias", 0.000001)
	lightComponent:call("set_ShadowVariance", 0)

    move_light_to_camera(lightGameObject)
	lightComponent:call("update")
	
    lightTableEntry = {
		id = lightNo,
        lightGameObject = lightGameObject,
        lightComponent = lightComponent,
        showLightEditor = false,
        attachedToCam = false,
		typeDescription = ternary(createSpotLight, "Spotlight ", "Pointlight "),
		isSpotLight = createSpotLight
    }

    table.insert( lTable, lightTableEntry )
end

local function get_new_light_no()
	lightCounter = lightCounter+1
	return lightCounter
end

--UI---------------------------------------------------------
local function ui_margin()
	imgui.text(" ")
	imgui.same_line()
end

local function handle_float_value(lightComponent, captionString, getterFuncName, setterFuncName, stepSize, min, max)
	ui_margin()
	changed, newValue = imgui.drag_float(captionString, lightComponent:call(getterFuncName), stepSize, min, max)
	if changed then lightComponent:call(setterFuncName, newValue) end
end

local function handle_bool_value(lightComponent, captionString, getterFuncName, setterFuncName)
	ui_margin()
	changed, enabledValue = imgui.checkbox(captionString, lightComponent:call(getterFuncName))
	if changed then lightComponent:call(setterFuncName, enabledValue) end
end

local function sliders_change_pos(lightGameObject)
    local lightGameObjectTransform = lightGameObject:call("get_Transform")
    local lightGameObjectPos = lightGameObjectTransform:get_position()
	local lightGameObjectAngles = lightGameObjectTransform:call("get_EulerAngle")
	
	if imgui.tree_node("Position / orientation") then
		-- X is right, Y is up, Z is out of the screen
		ui_margin()
		changedX, newXValue = imgui.drag_float("X (right)", lightGameObjectPos.x, 0.01, -10000, 10000)
		ui_margin()
		changedY, newYValue = imgui.drag_float("Y (up)", lightGameObjectPos.y, 0.01, -10000, 10000)
		ui_margin()
		changedZ, newZValue = imgui.drag_float("Z (out of the screen)", lightGameObjectPos.z, 0.01, -10000, 10000)

		ui_margin()
		changedPitch, newPitchValue = imgui.drag_float("Pitch", lightGameObjectAngles.x, 0.001, -3.1415924, 3.1415924)
		ui_margin()
		changedYaw, newYawValue = imgui.drag_float("Yaw", lightGameObjectAngles.y, 0.001, -3.1415924, 3.1415924)
		imgui.tree_pop()
	end
    if changedX or changedY or changedZ then
        if not changedX then newXValue = lightGameObjectPos.x end
        if not changedY then newYValue = lightGameObjectPos.y end
        if not changedZ then newZValue = lightGameObjectPos.z end
        lightGameObjectTransform:set_position(Vector3f.new(newXValue, newYValue, newZValue))
    end
	
	if changedPitch or changedYaw then
		if not changedPitch then newPitchValue = lightGameObjectAngles.x end
		if not changedYaw then newYawValue = lightGameObjectAngles.y end
		lightGameObjectTransform:call("set_EulerAngle", Vector3f.new(newPitchValue, newYawValue, lightGameObjectAngles.z))
		-- now grab the local matrix and write that as the world matrix, as the world matrix isn't updated but the local matrix is (and they should be the same)
		write_mat4(lightGameObjectTransform, 0x80, lightGameObjectTransform:call("get_LocalMatrix"))
	end
end

function main_menu()
	if imgui.tree_node("RELit v"..relitVersion) then

		if imgui.button("Add new spotlight") then 
			add_new_light(lightsTable, true, get_new_light_no())
		end
		imgui.same_line()
		if imgui.button("Add new pointlight") then 
			add_new_light(lightsTable, false, get_new_light_no())
		end

		for i, lightEntry in ipairs(lightsTable) do
			local lightGameObject = lightEntry.lightGameObject
			local lightComponent = lightEntry.lightComponent

			imgui.push_id(lightEntry.id)
			local changed, enabledValue = imgui.checkbox("", lightComponent:call("get_Enabled"))
			if changed then
				lightComponent:call("set_Enabled", enabledValue)
			end

			imgui.same_line()

			imgui.text(lightEntry.typeDescription..tostring(i))
			imgui.same_line()

			if imgui.button("Move To Camera") then 
				move_light_to_camera(lightGameObject)
			end

			imgui.same_line()

			local changed, attachedToCamValue = imgui.checkbox("Attach to camera", lightEntry.attachedToCam)
			if changed then
				lightEntry.attachedToCam = attachedToCamValue
			end

			imgui.same_line()

			if imgui.button(" Edit ") then
				lightEntry.showLightEditor = true
			end

			imgui.same_line()

			if imgui.button("Delete") then 
				lightGameObject:call("destroy", lightGameObject)
				table.remove(lightsTable, i)
			end

			imgui.pop_id()
		end

		imgui.text(" ")
		imgui.text("--------------------------------------------")
		imgui.text("RELit is (c) Originalnicodr & Otis_Inf")
		imgui.text("https://framedsc.com")
		imgui.text(" ")
		imgui.tree_pop()
	end
end

--Light Editor window UI-------------------------------------------------------
function light_editor_menu()
	for i, lightEntry in ipairs(lightsTable) do
		local lightGameObject = lightEntry.lightGameObject
		local lightComponent = lightEntry.lightComponent

		if lightEntry.attachedToCam then
			move_light_to_camera(lightGameObject)
		end

        if lightEntry.showLightEditor then

			imgui.push_id(lightEntry.id)
            lightEntry.showLightEditor = imgui.begin_window(lightEntry.typeDescription..tostring(i).." editor", true, 64)

            sliders_change_pos(lightGameObject)

			if imgui.tree_node("Light characteristics") then
				handle_float_value(lightComponent, "Intensity", "get_Intensity", "set_Intensity", 1, 0, 100000)

				imgui.spacing()
				ui_margin()
				
				changed, new_color = imgui.color_picker3("Light color", lightComponent:call("get_Color"))
				if changed then
					lightComponent:call("set_Color", new_color)
				end

				imgui.spacing()

				if gameName~="dmc5" then
					-- temperature settings don't work for some reason in DMC5
					handle_bool_value(lightComponent, "Use temperature", "get_BlackBodyRadiation", "set_BlackBodyRadiation")
					handle_float_value(lightComponent, "Temperature", "get_Temperature", "set_Temperature", 10, 1000, 20000)
				end
				handle_float_value(lightComponent, "Bounce intensity", "get_BounceIntensity", "set_BounceIntensity", 0.01, 0, 1000)
				handle_float_value(lightComponent, "Min roughness", "get_MinRoughness", "set_MinRoughness", 0.01, 0, 1.0)
				handle_float_value(lightComponent, "AO Efficiency", "get_AOEfficiency", "set_AOEfficiency", 0.0001, 0, 10)
				handle_float_value(lightComponent, "Volumetric scattering intensity", "get_VolumetricScatteringIntensity", "set_VolumetricScatteringIntensity", 0.01, 0, 100000)
				handle_float_value(lightComponent, "Radius", "get_Radius", "set_Radius", 0.01, 0, 100000)
				handle_float_value(lightComponent, "Illuminance Threshold", "get_IlluminanceThreshold", "set_IlluminanceThreshold", 0.01, 0, 100000)

				if lightEntry.isSpotLight then
					handle_float_value(lightComponent, "Cone", "get_Cone", "set_Cone", 0.01, 0, 1000)
					handle_float_value(lightComponent, "Spread", "get_Spread", "set_Spread", 0.01, 0, 100)
					handle_float_value(lightComponent, "Falloff", "get_Falloff", "set_Falloff", 0.01, 0, 100)
				end
				
				imgui.tree_pop()
			end
			
			if imgui.tree_node("Shadow settings") then
				imgui.spacing()
				handle_bool_value(lightComponent, "Enable shadows", "get_ShadowEnable", "set_ShadowEnable")
				handle_float_value(lightComponent, "Shadow bias", "get_ShadowBias", "set_ShadowBias", 0.0000001, 0, 1.0)
				handle_float_value(lightComponent, "Shadow blur", "get_ShadowVariance", "set_ShadowVariance", 0.0001, 0, 1.0)
				handle_float_value(lightComponent, "Shadow lod bias", "get_ShadowLodBias", "set_ShadowLodBias", 0.0000001, 0, 1.0)
				handle_float_value(lightComponent, "Shadow depth bias", "get_ShadowDepthBias", "set_ShadowDepthBias", 0.0000001, 0, 1.0)
				handle_float_value(lightComponent, "Shadow slope bias", "get_ShadowSlopeBias", "set_ShadowSlopeBias", 0.0000001, 0, 1.0)
				handle_float_value(lightComponent, "Shadow near plane", "get_ShadowNearPlane", "set_ShadowNearPlane", 0.00001, 0, 1.0)

				if lightEntry.isSpotLight then
					handle_float_value(lightComponent, "Detail shadow", "get_DetailShadow", "set_DetailShadow", 0.001, 0, 1.0)
				end 
				imgui.tree_pop()
			end
			
			imgui.spacing()
			imgui.text(" ")
			imgui.same_line()
			if imgui.button("Close") then
				lightEntry.showLightEditor = false
			end
			imgui.spacing()

            imgui.end_window()
			imgui.pop_id()
			lightComponent:call("update")
        end
    end
end

re.on_draw_ui(main_menu)
re.on_frame(light_editor_menu)