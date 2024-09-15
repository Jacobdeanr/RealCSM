-- TODO:
-- - Use a single ProjectedTexture when r_flashlightdepthres is 0 (since there's no shadows then anyway)

AddCSLuaFile()
-- use custom base_edit so we can work in any gamemose
DEFINE_BASECLASS("base_edit_csm")

--jit.opt.start(2) -- same as -O2
--jit.opt.start("-dce")
--jit.opt.start("hotloop=10", "hotexit=2")
--jit.on()
-- Above are some dumb experiments, don't include them 

ENT.Spawnable = true
ENT.AdminOnly = true

--ENT.Base = "base_edit"
ENT.PrintName = "CSM Editor"
ENT.Category = "Editors"

local sun = {
	direction = Vector(0, 0, 0),
	obstruction = 0,
}
local warnedyet = false
cvar_csm_legacydisablesun = CreateClientConVar(	 "csm_legacydisablesun", 0,  true, false)
cvar_csm_haslightenv = CreateClientConVar(	 "csm_haslightenv", 0,  false, false)
cvar_csm_hashdr = CreateClientConVar(	 "csm_hashdr", 0,  false, false)
cvar_csm_enabled = CreateClientConVar(	 "csm_enabled", 1,  false, false)

CreateClientConVar(	 "csm_update", 1,  false, false)
CreateClientConVar(	 "csm_filter", 0.08,  false, false)
CreateClientConVar(	 "csm_filter_distancescale", 1,  false, false)
CreateClientConVar(	 "csm_spread_layer_alloctype", 0,  false, false)
CreateClientConVar(	 "csm_spread_layer_reservemiddle", 1,  false, false)
CreateClientConVar(	 "csm_nofar", 0,  false, false)


CreateConVar(	 "csm_getENVSUNcolour", 1, FCVAR_ARCHIVE)
CreateConVar(	 "csm_stormfoxsupport", 0,  FCVAR_ARCHIVE)
CreateConVar(	 "csm_stormfox_brightness_multiplier", 1, FCVAR_ARCHIVE)
CreateConVar(	 "csm_stormfox_coloured_sun", 0, FCVAR_ARCHIVE)
local lightenvs = {ents.FindByClass("light_environment")}
local hasLightEnvs = false

local RemoveStaticSunPrev = false
local HideRTTShadowsPrev = false
local BlobShadowsPrev = false
local ShadowFilterPrev = 1.0
local DepthBiasPrev = 1.0
local SlopeScaleDepthBiasPrev = 1.0
local shadfiltChanged = true
local csmEnabledPrev = false
local useskyandfog = false
local furtherEnabled = false
local furtherEnabledPrev = false
local furtherEnabledShadows = false
local furtherEnabledShadowsPrev = false
local harshCutoff = false
local harshCutoffPrev = false
local farEnabledShadows = true
local farEnabledShadowsPrev = true
local spreadEnabled = false
local spreadEnabledPrev = false
local spreadSample = 6
local spreadSamplePrev = 6
local spreadLayer = 1
local spreadLayerPrev = 0
local spreadRadiusPrev = 0
local propradiosity = 4
local propradiosityPrev = 4
local perfMode = false
local perfModePrev = false
local fpShadowsPrev = false

local fpshadowcontroller
local fpshadowcontrollerCLIENT

local lightAlloc = {} -- var PISS --old name for reference, maybe stop using dumb names
--local SHIT = {} -- var SHIT
local lightPoints = {} -- var FUCK

-- https://youtu.be/gTR2TVXbMGI?t=102
-- fix for 1:48
function SkyBoxFixOn()
	
	local fog_controller = ents.FindByClass("env_fog_controller")[1]
	if (fog_controller) then 
		fog_controller:SetKeyValue("farz", 80000)
	end
	RunConsoleCommand("r_farz", "80000")
	--hook.Add( "PreDrawOpaqueRenderables", "RealCSMSkyboxViewFix",  SkyBoxFixFunction)
end

function SkyBoxFixOff()
	
	if (fog_controller) then 
		fog_controller:SetKeyValue("farz", -1)
	end
	RunConsoleCommand("r_farz", "-1")
	--hook.Remove( "PreDrawOpaqueRenderables", "RealCSMSkyboxViewFix")
end
function SkyBoxFixFunction(isDrawingDepth, isDrawSkybox, isDraw3DSkybox )
	
	
	if (!isDrawSkybox) then return nil end
	if (isDraw3DSkybox) then return nil end
	--if (GetConVar( "csm_enabled" ):GetInt() != 1) then return nil end
	--if (GetConVar( "csm_skyboxfix" ):GetInt() != 1) then return nil end
	--render.SuppressEngineLighting( isDrawSkybox && !isDraw3DSkybox )
	render.DepthRange(0.01,1)
	render.EnableClipping(false)
	--render.FogEnd(80000)
	--print("gi")
end

if (CLIENT) then
	if (render.GetHDREnabled()) then
		RunConsoleCommand("csm_hashdr", "1")
	else
		RunConsoleCommand("csm_hashdr", "0")
	end
end
if (SERVER) then
	util.AddNetworkString( "killCLientShadowsCSM" )
	util.AddNetworkString( "PlayerSpawned" )
	util.AddNetworkString( "hasLightEnvNet" )
	util.AddNetworkString( "csmPropWakeup" )
	util.AddNetworkString( "ReloadLightMapsCSM" )
	if (table.Count(ents.FindByClass("light_environment")) > 0) then
		RunConsoleCommand("csm_haslightenv", "1")
	end
end
local AppearanceKeys = {
	{ Position = 0.00, SunColour = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.00, 0.00), SkyDuskColor = Vector(0.00, 0.00, 0.00), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) },
	{ Position = 0.25, SunColour = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.00, 0.00), SkyDuskColor = Vector(0.00, 0.03, 0.03), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) },
	{ Position = 0.30, SunColour = Color(255,  140,  0, 255), SunBrightness = 0.3, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.01, 0.00, 0.03), SkyBottomColor = Vector(0.00, 0.05, 0.11), SkyDuskColor = Vector(1.00, 0.16, 0.00), SkySunColor = Vector(0.73, 0.24, 0.00), FogColor = Vector(153, 110, 125) },
	{ Position = 0.35, SunColour = Color(255, 217, 179, 255), SunBrightness = 1.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.06, 0.21, 0.39), SkyBottomColor = Vector(0.02, 0.26, 0.39), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.27, 0.11, 0.05), FogColor = Vector( 94, 148, 199) },
	{ Position = 0.50, SunColour = Color(255, 217, 179, 255), SunBrightness = 1.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.18, 1.00), SkyBottomColor = Vector(0.00, 0.34, 0.67), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.27, 0.11, 0.05), FogColor = Vector( 94, 148, 199) },
	{ Position = 0.65, SunColour = Color(255, 217, 179, 255), SunBrightness = 1.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.06, 0.21, 0.39), SkyBottomColor = Vector(0.02, 0.26, 0.39), SkyDuskColor = Vector(0.29, 0.31, 0.00), SkySunColor = Vector(0.27, 0.11, 0.05), FogColor = Vector( 94, 148, 199) },
	{ Position = 0.70, SunColour = Color(255,  140,  0, 255), SunBrightness = 0.3, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.01, 0.00, 0.03), SkyBottomColor = Vector(0.00, 0.05, 0.11), SkyDuskColor = Vector(1.00, 0.16, 0.00), SkySunColor = Vector(0.73, 0.24, 0.00), FogColor = Vector(153, 110, 125) },
	{ Position = 0.75, SunColour = Color(  0,   0,   0, 255), SunBrightness =  0.0, ScreenDarkenFactor = 0.0, SkyTopColor = Vector(0.00, 0.00, 0.00), SkyBottomColor = Vector(0.00, 0.00, 0.00), SkyDuskColor = Vector(0.00, 0.03, 0.03), SkySunColor = Vector(0.00, 0.00, 0.00), FogColor = Vector( 23,  36,  41) }
}

net.Receive( "hasLightEnvNet", function( len, ply )
	RunConsoleCommand("csm_haslightenv", "1")
end)
function wakeup()
	if SERVER and GetConVar("csm_allowwakeprops"):GetBool() then
		print("[Real CSM] - Radiosity changed, waking up all props. (csm_wakeprops = 1)")
		for k, v in ipairs(ents.FindByClass( "prop_physics" )) do
			v:Fire("wake")
		end
	end
end
function findlight()
	if (SERVER) then
		hasLightEnvs = (table.Count(lightenvs) > 0)
		if (table.Count(ents.FindByClass("light_environment")) > 0) then
			RunConsoleCommand("csm_haslightenv", "1")
			net.Start( "hasLightEnvNet" )
			net.Broadcast()
		else
			RunConsoleCommand("csm_haslightenv", "0")
		end
	end
end
function warn()
	findlight()
	if CLIENT and (GetConVar( "csm_haslightenv" ):GetInt() == 0 && !GetConVar( "csm_disable_warnings" ):GetBool()) then
		Derma_Message( "This map has no named light_environment, the CSM will not look nearly as good as it could.", "CSM Alert!", "OK!" )
	end
	--print(hasLightEnvs)
end

function ENT:createlamps()
	self.ProjectedTextures = { }
	for i = 1, 3 do
		self.ProjectedTextures[i] = ProjectedTexture()
		self.ProjectedTextures[i]:SetEnableShadows(true)
		if (i == 1) then
			self.ProjectedTextures[i]:SetTexture("csm/mask_center")
			if perfMode then
				self.ProjectedTextures[i]:Remove()
			end
		else
			if (i == 2) and perfMode then
				self.ProjectedTextures[i]:SetTexture("csm/mask_center")
			else
				self.ProjectedTextures[i]:SetTexture("csm/mask_ring")
			end
		end
	end
	if (furtherEnabled or !harshCutoff) then
		self.ProjectedTextures[3]:SetTexture("csm/mask_ring") 
	else
		self.ProjectedTextures[3]:SetTexture("csm/mask_end")
	end
	if spreadEnabled and CLIENT then
		self:allocLights()
		self.ProjectedTextures[2]:SetTexture("csm/mask_center")
		for i = 1, GetConVar( "csm_spread_samples"):GetInt() - 2 do
			self.ProjectedTextures[i + 4] = ProjectedTexture()
			self.ProjectedTextures[i + 4]:SetEnableShadows(true)
			self.ProjectedTextures[i + 4]:SetTexture("csm/mask_center")
		end
	end


end

function ENT:SUNOff()
	if (SERVER) then -- TODO: make this turn off only on the client
		for k, v in ipairs(ents.FindByClass( "light_environment" )) do
			v:Fire("turnoff")
		end
	end
end
function ENT:SUNOn()
	if (SERVER) then -- TODO: make this turn off only on the client
		for k, v in ipairs(ents.FindByClass( "light_environment" )) do
			v:Fire("turnon")
		end
		net.Start( "ReloadLightMapsCSM" )
		net.Broadcast()
	end
end

function ENT:Initialize()
	for k, v in ipairs(ents.FindByClass( "edit_csm" )) do
		if v != self and SERVER then
			net.Start( "killCLientShadowsCSM" )
			net.Broadcast()
			v:Remove()
		end
	end
	--RunConsoleCommand("r_projectedtexture_filter", "0.1")
	if !GetConVar( "csm_blobbyao" ):GetBool() then
		DisableRTT()
	else
		BlobShadowsPrev = false
	end
	shadfiltChanged = true

	RunConsoleCommand("csm_enabled", "1")
	
	
	-- https://youtu.be/gTR2TVXbMGI?t=102
	-- fix for 1:48
	SkyBoxFixOn()

	if CLIENT and (file.Read( "realcsm.txt", "DATA" ) != "two" ) then
		--Derma_Message( "Hello! Welcome to the CSM addon! You should raise r_flashlightdepthres else the shadows will be blocky! Make sure you've read the FAQ for troubleshooting.", "CSM Alert!", "OK!" )
		local Frame = vgui.Create( "DFrame" )
		Frame:SetSize( 330, 290 )

		RunConsoleCommand("r_flashlightdepthres", "1024") -- set it to the lowest of the low to avoid crashes

		Frame:Center()
		Frame:SetTitle( "CSM First Time Spawn!" )
		Frame:SetVisible( true )
		Frame:SetDraggable( false )
		Frame:ShowCloseButton( true )
		Frame:MakePopup()
		local label1 = vgui.Create( "DLabel", Frame )
		label1:SetPos( 15, 40 )
		label1:SetSize(	300, 20)
		label1:SetText( "Welcome to Real CSM!" )
		label1:SetTextColor( Color( 255, 255, 255) )
		local label2 = vgui.Create( "DLabel", Frame )
		label2:SetPos( 15, 70 )
		label2:SetSize(	300, 20)
		label2:SetText( "This is your first time spawning CSM, go set your quality!" )
		
		local label3 = vgui.Create( "DLabel", Frame )
		label3:SetPos( 15, 85 )
		label3:SetSize(	300, 20)
		label3:SetText( "Refer to the F.A.Q for troubleshooting and help!" )
		
		local label4 = vgui.Create( "DLabel", Frame )
		label4:SetPos( 15, 100 )
		label4:SetSize(	300, 20)
		label4:SetText( "More settings can be found in the spawnmenu's \"Utilities\" tab" )


		local DermaNumSlider = vgui.Create( "DNumSlider", Frame )
		DermaNumSlider:SetPos( 15, 130 )				-- Set the position
		DermaNumSlider:SetSize( 300, 30 )			-- Set the size
		DermaNumSlider:SetText( "Shadow Quality" )	-- Set the text above the slider
		DermaNumSlider:SetMin( 0 )				 	-- Set the minimum number you can slide to
		DermaNumSlider:SetMax( 8192 )				-- Set the maximum number you can slide to
		DermaNumSlider:SetDecimals( 0 )				-- Decimal places - zero for whole number
		DermaNumSlider:SetConVar( "r_flashlightdepthres" )	-- Changes the ConVar when you slide

		
		local lowButton = vgui.Create("DButton", Frame)
		lowButton:SetText( "Low" )
		lowButton:SetPos( 15, 160 )
		local mediumButton = vgui.Create("DButton", Frame)
		mediumButton:SetText( "Medium" )
		mediumButton:SetPos( 135, 160 )
		local highButton = vgui.Create("DButton", Frame)
		highButton:SetText( "High" )
		highButton:SetPos( 255, 160 )
		highButton.DoClick = function()
			RunConsoleCommand("r_flashlightdepthres", "8192")
		end
		mediumButton.DoClick = function()
			RunConsoleCommand("r_flashlightdepthres", "4096")
		end
		lowButton.DoClick = function()
			RunConsoleCommand("r_flashlightdepthres", "2048")
		end

		--local DermaNumSlider2 = vgui.Create( "DNumSlider", Frame )
		--DermaNumSlider2:SetPos( 8, 140 )				-- Set the position
		--DermaNumSlider2:SetSize( 300, 30 )			-- Set the size
		--DermaNumSlider2:SetText( "Shadow Filter" )	-- Set the text above the slider
		--DermaNumSlider2:SetMin( 0 )				 	-- Set the minimum number you can slide to
		--DermaNumSlider2:SetMax( 10 )				-- Set the maximum number you can slide to
		--DermaNumSlider2:SetDecimals( 2 )				-- Decimal places - zero for whole number
		--DermaNumSlider2:SetConVar( "r_projectedtexture_filter" )	-- Changes the ConVar when you slide

		local DermaCheckbox2 = vgui.Create( "DCheckBoxLabel", Frame )
		DermaCheckbox2:SetText("Performance Mode")
		DermaCheckbox2:SetPos( 15, 195 )				-- Set the position
		DermaCheckbox2:SetSize( 300, 30 )			-- Set the size
		DermaCheckbox2:SetTextColor( Color( 255, 255, 255) )
		DermaCheckbox2:SetConVar( "csm_perfmode" )

		local label5 = vgui.Create( "DLabel", Frame )
		label5:SetPos( 39, 215 )
		label5:SetSize(	300, 20)
		label5:SetTextColor( Color( 180, 180, 180) )
		label5:SetText( "Use less shadow cascades for increased performance." )

		local Button = vgui.Create("DButton", Frame)
		Button:SetText( "Continue" )
		Button:SetPos( 175, 250 )
		local Button2 = vgui.Create("DButton", Frame)
		Button2:SetText( "Cancel" )
		Button2:SetPos( 95, 250 )
		Button.DoClick = function()
			file.Write( "realcsm.txt", "two" )
			Frame:Close()
		end

		Button2.DoClick = function()
			RunConsoleCommand("csm_enabled", "0")
			Frame:Close()
		end
	end

	if (SERVER) then
		if GetConVar( "csm_allowfpshadows_old" ):GetBool() then
			fpshadowcontroller = ents.Create( "csm_pseudoplayer_old" )
			fpshadowcontroller:Spawn()
		end
		util.AddNetworkString( "PlayerSpawned" )
		hasLightEnvs = (table.Count(lightenvs) > 0)
		if hasLightEnvs then
			self:SetRemoveStaticSun(true)
		else
			self:SetRemoveStaticSun(false)
			timer.Create( "warn", 0.1, 1, warn)
		end
	else
		fpShadowsPrev = !GetConVar( "csm_localplayershadow" ):GetBool()
		timer.Create( "warn", 0.1, 1, warn)
	end

	BaseClass.Initialize(self)
	self:SetMaterial( "csm/edit_csm" )
	if (self:GetRemoveStaticSun()) then
		timer.Create( "warn", 0.1, 1, warn)
		RunConsoleCommand("r_radiosity", GetConVar( "csm_propradiosity" ):GetString())
		if (GetConVar( "csm_wakeprops" ):GetBool()) then
			wakeup()
		end
		if (GetConVar( "csm_legacydisablesun" ):GetInt() == 1) then
			RunConsoleCommand("r_lightstyle", "0")
			RunConsoleCommand("r_ambientlightingonly", "1")
			if (CLIENT) then
				timer.Create( "reload", 0.1, 1, reloadLightmaps)
			end
		else
			self:SUNOff()
		end
	end

	if (CLIENT) then
		self:createlamps()
	end
		--hook.Add("RenderScreenspaceEffects", "CsmRenderOverlay", RenderOverlay)
		--hook.Add("SetupWorldFog", self, self.SetupWorldFog )

	--if (SERVER) then
		--self.EnvSun = FindEntity("env_sun")
		--self.EnvFogController = FindEntity("env_fog_controller")
	--else
		--self.EnvSun = FindEntity("C_Sun")
		--self.EnvFogController = FindEntity("C_FogController")
	--end

	--self.EnvSkyPaint = FindEntity("env_skypaint")
end

function ENT:SetupWorldFog()
	--render.FogMode(1)
	--render.FogStart(0.0)
	--render.FogEnd(32768.0)
	--render.FogMaxDensity(0.9)
	--render.FogColor(self.CurrentAppearance.FogColor.x, self.CurrentAppearance.FogColor.y, self.CurrentAppearance.FogColor.z)

	return false
end

function ENT:SetupDataTables()
	self:NetworkVar("Vector", 0, "SunColour", { KeyName = "Sun colour", Edit = { type = "VectorColor", order = 2, title = "Sun colour"}})
	self:NetworkVar("Float", 0, "SunBrightness", { KeyName = "Sun brightness", Edit = { type = "Float", order = 3, min = 0.0, max = 10000.0, title = "Sun brightness"}})

	self:NetworkVar("Float", 1, "SizeNear", { KeyName = "Size 1", Edit = { type = "Float", order = 4, min = 0.0, max = 32768.0, title = "Near cascade size" }})
	self:NetworkVar("Float", 2, "SizeMid",  { KeyName = "Size 2", Edit = { type = "Float", order = 5, min = 0.0, max = 32768.0, title = "Middle cascade size" }})
	self:NetworkVar("Float", 3, "SizeFar",  { KeyName = "Size 3", Edit = { type = "Float", order = 6, min = 0.0, max = 32768.0, title = "Far cascade size" }}) --16384

	--self:NetworkVar("Bool", 0, "EnableFurther", { KeyName = "Enable Futher Light", Edit = { type = "Bool", order = 7, title = "Enable further cascade for large maps"}})
	self:NetworkVar("Float", 4, "SizeFurther",  { KeyName = "Size 4", Edit = { type = "Float", order = 8, min = 0.0, max = 65536.0, title = "Further cascade size" }})
	--self:NetworkVar("Bool", 1, "EnableFurtherShadows", { KeyName = "Enable Futher Shadows", Edit = { type = "Bool", order = 7, title = "Enable shadows on further cascade"}})

	self:NetworkVar("Float", 5, "Orientation", { KeyName = "Orientation", Edit = { type = "Float", order = 10, min = 0.0, max = 360.0, title = "Sun orientation" }})
	self:NetworkVar("Bool", 2, "UseMapSunAngles", { KeyName = "Use Map Sun Angles", Edit = { type = "Bool", order = 11, title = "Use the Map Sun angles"}})
	self:NetworkVar("Bool", 3, "UseSkyFogEffects", { KeyName = "Use Sky and Fog Effects", Edit = { type = "Bool", order = 12, title = "Use Sky and Fog effects"}})
	self:NetworkVar("Float", 6, "MaxAltitude", { KeyName = "Maximum altitude", Edit = { type = "Float", order = 13, min = 0.0, max = 90.0, title = "Maximum altitude" }})
	self:NetworkVar("Float", 7, "Time", { KeyName = "Time", Edit = { type = "Float", order = 14, min = 0.0, max = 1.0, title = "Time of Day" }})
	self:NetworkVar("Float", 9, "Height", { KeyName = "Height", Edit = { type = "Float", order = 15, min = 0.0, max = 50000.0, title = "Sun Height" }})
	self:NetworkVar("Float", 10, "SunNearZ", { KeyName = "NearZ", Edit = { type = "Float", order = 16, min = 0.0, max = 32768.0, title = "Sun NearZ (adjust if issues)" }})
	self:NetworkVar("Float", 11, "SunFarZ", { KeyName = "FarZ", Edit = { type = "Float", order = 17, min = 0.0, max = 50000.0, title = "Sun FarZ" }})

	self:NetworkVar("Bool", 4, "RemoveStaticSun", { KeyName = "Remove Vanilla Static Sun", Edit = { type = "Bool", order = 18, title = "Remove vanilla static Sun"}})
	self:NetworkVar("Bool", 5, "HideRTTShadows", { KeyName = "Hide RTT Shadows", Edit = { type = "Bool", order = 19, title = "Hide RTT Shadows"}})

	--self:NetworkVar("Float", 10, "ShadowFilter", { KeyName = "ShadowFilter", Edit = { type = "Float", order = 19, min = 0.0, max = 10.0, title = "Shadow filter"}})
	--self:NetworkVar("Int", 3, "ShadowRes", { KeyName = "ShadowRes", Edit = { type = "Float", order = 20, min = 0.0, max = 8192.0, title = "Shadow resolution"}})

	self:NetworkVar("Bool", 6, "EnableOffsets", { KeyName = "Enable Offsets", Edit = { type = "Bool", order = 21, title = "Enable Offsets"}})
	self:NetworkVar("Int", 0, "OffsetPitch", { KeyName = "Pitch Offset", Edit = { type = "Float", order = 22, min = -180.0, max = 180.0, title = "Pitch Offset" }})
	self:NetworkVar("Int", 1, "OffsetYaw", { KeyName = "Yaw Offset", Edit = { type = "Float", order = 23, min = -180.0, max = 180.0, title = "Yaw Offset" }})
	self:NetworkVar("Int", 2, "OffsetRoll", { KeyName = "Roll Offset", Edit = { type = "Float", order = 24, min = -180.0, max = 180.0, title = "Roll Offset" }})

	if (SERVER) then
		-- Yeah I hardcoded the construct sun colour, the env_suns one is shit
		if GetConVar( "csm_getENVSUNcolour"):GetBool() and game.GetMap() != "gm_construct" and FindEntity("env_sun") != nil then
			self:SetSunColour(FindEntity("env_sun"):GetColor():ToVector()) --Vector(1.0, 0.90, 0.80, 1.0))
		else
			self:SetSunColour(Vector(1.0, 0.90, 0.80, 1.0))
		end
		if (GetConVar( "csm_hashdr" ):GetInt() == 1) then
			self:SetSunBrightness(1000)
		else
			self:SetSunBrightness(200)
		end

		self:SetSizeNear(128.0)
		self:SetSizeMid(1024.0)
		self:SetSizeFar(8192.0)

		--self:SetEnableFurther(false)
		self:SetSizeFurther(65536.0)
		--self:SetEnableFurtherShadows(true)


		self:SetUseMapSunAngles(true)
		self:SetUseSkyFogEffects(false)
		self:SetOrientation(135.0)
		self:SetMaxAltitude(50.0)
		self:SetTime(0.5)
		self:SetHeight(32768)
		self:SetSunNearZ(25000.0)
		self:SetSunFarZ(49152.0)

		self:SetRemoveStaticSun(true)
		self:SetHideRTTShadows(true)
		--self:SetShadowFilter(0.1)
		--self:SetShadowRes(8192)

		self:SetEnableOffsets(false)
		self:SetOffsetPitch(0)
		self:SetOffsetYaw(0)
		self:SetOffsetRoll(0)
		shadfiltChanged = true
	end
end

hook.Add( "PlayerInitialSpawn", "playerspawned", function( ply )
	net.Start( "PlayerSpawned" )
	net.Send( ply )
end )


net.Receive( "PlayerSpawned", function( len, ply )
	if CLIENT and (FindEntity("edit_csm") != nil) and (GetConVar( "csm_spawnalways" ):GetBool()) then
		FindEntity("edit_csm"):Initialize()
	end
end )

net.Receive( "ReloadLightMapsCSM", function( len, ply )
	if CLIENT and GetConVar("csm_redownloadonremove"):GetBool() then
		render.RedownloadAllLightmaps(false ,true)
	end
end )

net.Receive( "csmPropWakeup", function( len, ply )
	if SERVER then
		wakeup()
	end
end )

net.Receive( "killCLientShadowsCSM", function( len, ply )
	if CLIENT and fpshadowcontrollerCLIENT and fpshadowcontrollerCLIENT:IsValid() then
		fpshadowcontrollerCLIENT:Remove()
	end
end )

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end


function reloadLightmaps()
	if (CLIENT) then
		render.RedownloadAllLightmaps(false ,true)
	end
end

function ENT:OnRemove()
	if fpshadowcontrollerCLIENT and fpshadowcontrollerCLIENT:IsValid() then
		fpshadowcontrollerCLIENT:Remove()
	end
	
	SkyBoxFixOff()

	if (GetConVar( "csm_spawnalways" ):GetInt() == 0) then
		furtherEnabled = false
		furtherEnabledPrev = false
		if (self:GetHideRTTShadows()) then
			EnableRTT()
		end
		if GetConVar( "csm_blobbyao" ):GetBool() then
			RunConsoleCommand("r_shadowrendertotexture", "1")
			RunConsoleCommand("r_shadowdist", "10000")
		end

		if (self:GetRemoveStaticSun()) then

			RunConsoleCommand("r_radiosity", "3")
			if (GetConVar( "csm_wakeprops" ):GetBool()) then
				wakeup()
			end
			if (GetConVar( "csm_legacydisablesun" ):GetInt() == 1) then
				RunConsoleCommand("r_ambientlightingonly", "0")

				RunConsoleCommand("r_lightstyle", "-1")
				timer.Create( "reload", 0.1, 1, reloadLightmaps )
			else
				self:SUNOn()
			end
		end
	end
	if SERVER and fpshadowcontroller and fpshadowcontroller:IsValid() then
		fpshadowcontroller:Remove()

	end
	if (CLIENT) then
		for i, projectedTexture in pairs(self.ProjectedTextures) do
			projectedTexture:Remove()
		end

		table.Empty(self.ProjectedTextures)
	end
end

rttenabled = true 

function EnableShadowFix(ent)
	if (ent:GetRenderGroup() == RENDERGROUP_TRANSLUCENT && GetConVar( "csm_experimental_translucentshadows" ):GetBool()) then
		ent.RenderOverride = ShadowFix
	end
end
function ShadowFix( self, flags )
	-- WHY THE FUCK DOES THIS WORK???????? 
	if (self:GetRenderMode() != RENDERMODE_NONE) then
		self:SetRenderMode( RENDERMODE_NONE )
	end
	self:DrawModel( flags )
	render.OverrideDepthEnable(false   ,true    )
end

function DisableRTTHook(ent)
	ent:DrawShadow( ent.stored_shadow_value or true )
	EnableShadowFix(ent)
end


function DisableRTT()
	if (rttenabled == false) then return end
	if (SERVER) then return end
	rttenabled = false
	print("[Real CSM] - Disabling RTT Shadows")
	RunConsoleCommand("r_shadows_gamecontrol", "0")
	hook.Add( "OnEntityCreated", "RealCSMDisableRTTHook", DisableRTTHook)
	for k, v in pairs(ents.GetAll()) do
		v:DrawShadow( v.stored_shadow_value or true )
	end
end

function EnableRTT()
	if (rttenabled == true) then return end
	if (SERVER) then return end
	rttenabled = true 
	print("[Real CSM] - Enabling RTT Shadows")
	RunConsoleCommand("r_shadows_gamecontrol", "1")
	hook.Remove( "OnEntityCreated", "RealCSMDisableRTTHook" )
	for k, v in pairs(ents.GetAll()) do
		v:DrawShadow(v.stored_shadow_value or true ) 
	end
end

local meta = FindMetaTable("Entity")

meta.oldsh = meta.oldsh or meta.DrawShadow
function meta:DrawShadow(val)
	if (rttenabled) then
		self.stored_shadow_value = val
		self:oldsh( val )
	else
		self:oldsh( false )
	end
end

hook.Add( "ShadnowFilterChange", "shadfiltchanged", function()
	shadfiltChanged = true
end)

-- Gods why am I doing all this?
function ENT:ManageCSMState(csmEnabled, csmWakeProps, csmPropRadiosity)
    if csmEnabled and not csmEnabledPrev then
        self:EnableCSM(csmWakeProps, csmPropRadiosity)
    elseif not csmEnabled and csmEnabledPrev then
        self:DisableCSM(csmWakeProps)
    end
end

function ENT:EnableCSM(csmWakeProps, csmPropRadiosity)
    furtherEnabledShadowsPrev = not GetConVar("csm_furthershadows"):GetBool()
    furtherEnabledPrev = not GetConVar("csm_further"):GetBool()
    csmEnabledPrev = true

    if self:GetRemoveStaticSun() then
        self:RemoveStaticSun()
    end

    RunConsoleCommand("r_radiosity", csmPropRadiosity)
    if csmWakeProps then wakeup() end
    self:ManageRTTForCSMEnable()

    if CLIENT then self:createlamps() end
end

function ENT:DisableCSM(csmWakeProps)
    csmEnabledPrev = false

    if self:GetRemoveStaticSun() then
        self:RestoreStaticSun()
    end

    RunConsoleCommand("r_radiosity", "3")
    if csmWakeProps then wakeup() end
    self:ManageRTTForCSMDisable()

    if CLIENT then self:ClearProjectedTextures() end
end

function ENT:RemoveStaticSun()
    if GetConVar("csm_legacydisablesun"):GetInt() == 1 then
        self:SetLegacySun(false)
    else
        self:SUNOff()
    end
end

function ENT:RestoreStaticSun()
    if GetConVar("csm_legacydisablesun"):GetInt() == 1 then
        self:SetLegacySun(true)
    else
        self:SUNOn()
    end
end

function ENT:SetLegacySun(enable)
    local ambient = enable and "1" or "0"
    local lightstyle = enable and "1" or "-1"
    RunConsoleCommand("r_ambientlightingonly", ambient)
    RunConsoleCommand("r_lightstyle", lightstyle)
    timer.Create("reload", 0.1, 1, reloadLightmaps)
end

function ENT:ManageRTTForCSMEnable()
    if self:GetHideRTTShadows() then
        DisableRTT()
        BlobShadowsPrev = false
    end

    if GetConVar("csm_blobbyao"):GetBool() then
        EnableRTT()
        RunConsoleCommand("r_shadowrendertotexture", "0")
        RunConsoleCommand("r_shadowdist", "20")
    end
end

function ENT:ManageRTTForCSMDisable()
    RunConsoleCommand("r_shadowrendertotexture", "1")
    RunConsoleCommand("r_shadowdist", "10000")
    if self:GetHideRTTShadows() then EnableRTT() end
end

function ENT:UpdateRadiosityIfNeeded(csmEnabled, csmPropRadiosity, csmWakeProps)
    if CLIENT and csmEnabled and (propradiosityPrev ~= csmPropRadiosity) then
        RunConsoleCommand("r_radiosity", csmPropRadiosity)
        if csmWakeProps then
            net.Start("csmPropWakeup")
            net.SendToServer()
        end
        propradiosityPrev = csmPropRadiosity
    end
end

function ENT:ManageFPSController(fpShadows)
    if fpShadowsPrev ~= fpShadows then
        if fpShadows then
            fpshadowcontrollerCLIENT = ents.CreateClientside("csm_pseudoplayer")
            fpshadowcontrollerCLIENT:Spawn()
        elseif fpshadowcontrollerCLIENT and fpshadowcontrollerCLIENT:IsValid() then
            fpshadowcontrollerCLIENT:Remove()
        end
        fpShadowsPrev = fpShadows
    end
end

function ENT:ManageFurtherShadows(furtherEnabled, harshCutoff, csmFurtherShadows)
    if furtherEnabledPrev ~= furtherEnabled then
        if furtherEnabled then
            self.ProjectedTextures[4] = self.ProjectedTextures[4] or ProjectedTexture()
            self.ProjectedTextures[4]:SetTexture(harshCutoff and "csm/mask_end" or "csm/mask_ring")
            self.ProjectedTextures[4]:SetEnableShadows(csmFurtherShadows)
        elseif self.ProjectedTextures[4] and self.ProjectedTextures[4]:IsValid() then
            self.ProjectedTextures[4]:Remove()
            self.ProjectedTextures[3]:SetTexture(harshCutoff and "csm/mask_end" or "csm/mask_ring")
        end
        furtherEnabledPrev = furtherEnabled
    end
end

function ENT:ManageFarShadows(csmFarShadows, csmNoFar)
    if farEnabledShadowsPrev ~= csmFarShadows then
        local projTex3 = self.ProjectedTextures[3]
        if projTex3 and projTex3:IsValid() then
            projTex3:SetEnableShadows(not csmFarShadows)
        end
        farEnabledShadowsPrev = csmFarShadows
    end

    if csmNoFar then
        local projTex3 = self.ProjectedTextures[3]
        if projTex3 and projTex3:IsValid() then
            projTex3:Remove()
        end
    end
end

function ENT:HandleSpreadSamples(csmSpreadSamples)
    if spreadSamplePrev ~= csmSpreadSamples then
        for _, projectedTexture in pairs(self.ProjectedTextures) do
            projectedTexture:Remove()
        end
        table.Empty(self.ProjectedTextures)
        self:createlamps()
        spreadSamplePrev = csmSpreadSamples
    end
end

function ENT:UpdateSpreadLayersAndRadius()
    local spreadLayer = GetConVar("csm_spread_layers"):GetInt()
    if spreadLayerPrev ~= spreadLayer then
        self:allocLights()
        spreadLayerPrev = spreadLayer
    end

    local spreadRadius = GetConVar("csm_spread_radius"):GetFloat()
    if spreadRadiusPrev ~= spreadRadius then
        self:allocLights()
        spreadRadiusPrev = spreadRadius
    end
end

function ENT:ManageSunEffects(csmPropRadiosity, csmWakeProps)
    local removestatsun = self:GetRemoveStaticSun()
    if RemoveStaticSunPrev ~= removestatsun then
        if removestatsun then
            self:RemoveStaticSun()
        else
            self:RestoreStaticSun()
        end
        RemoveStaticSunPrev = removestatsun
    end
end

function ENT:ManageRTTShadows(blobShadows)
    local hiderttshad = self:GetHideRTTShadows()

    if (HideRTTShadowsPrev ~= hiderttshad) and not blobShadows then
        if hiderttshad then
            DisableRTT()
        else
            EnableRTT()
        end
        HideRTTShadowsPrev = hiderttshad
    end
end

function ENT:ManageBlobShadows(csmEnabled, blobShadows)
    if (BlobShadowsPrev ~= blobShadows) and csmEnabled then
        BlobShadowsPrev = blobShadows
        if blobShadows then
            HideRTTShadowsPrev = true
            RunConsoleCommand("r_shadowrendertotexture", "0")
            RunConsoleCommand("r_shadowdist", "20")
            EnableRTT()
        else
            RunConsoleCommand("r_shadowrendertotexture", "1")
            RunConsoleCommand("r_shadowdist", "10000")
            if self:GetHideRTTShadows() then
                DisableRTT()
            else
                EnableRTT()
            end
        end
    end
end

function ENT:ClearProjectedTextures()
    for _, projectedTexture in pairs(self.ProjectedTextures) do
        projectedTexture:Remove()
    end
    table.Empty(self.ProjectedTextures)
end

function ENT:CalculateSunAngles()
    local pitch, yaw, roll

    if not self:GetUseMapSunAngles() then
        -- Default calculation when not using map sun angles
        pitch = -180.0 + (self:GetTime() * 360.0)
        yaw = self:GetOrientation()
        roll = 90.0 - self:GetMaxAltitude()
    else
        -- Try to use sun angles first
        local sun = util.GetSunInfo()
        if sun then
            local sunAngles = sun.direction:Angle()
            pitch, yaw, roll = sunAngles.pitch + 90, sunAngles.yaw, sunAngles.roll
        else
            -- Fallback to shadow control if no sun info
            local shadowControl = FindEntity("shadow_control")
            if shadowControl then
                local shadowAngles = shadowControl:GetAngles()
                pitch, yaw, roll = shadowAngles.pitch + 90, shadowAngles.yaw, shadowAngles.roll
            else
                -- No sun or shadow control; warn and use default rotation
                if not warnedyet and not GetConVar("csm_disable_warnings"):GetBool() then
                    Derma_Message("This map has no env_sun. CSM will not be able to find the sun position and rotation!", "CSM Alert!", "OK!")
                    warnedyet = true
                end

                pitch = -180.0 + (self:GetTime() * 360.0)
                yaw = self:GetOrientation()
                roll = 90.0 - self:GetMaxAltitude()
            end
        end
    end

    -- Apply any offsets
    if self:GetEnableOffsets() then
        pitch = pitch + self:GetOffsetPitch()
        yaw = yaw + self:GetOffsetYaw()
        roll = roll + self:GetOffsetRoll()
    end

    return pitch, yaw, roll
end


function ENT:CalculateOffsets(pitch, yaw, roll, usemapangles)
    local offset = Vector(0, 0, 1)
    local offset2 = Vector(0, 0, 1)
    
    offset:Rotate(Angle(pitch, 0, 0))
    offset:Rotate(Angle(0, yaw, roll))
    offset2:Rotate(Angle(pitch, 0, 0))
    offset2:Rotate(Angle(0, yaw, roll))
    
    if usemapangles then
        return offset2, offset2
    else
        return offset, offset2
    end
end

function ENT:CalculateMainPos(positionRounding)
    local mainpos = Vector()
    if CLIENT then
        mainpos = GetViewEntity():GetPos()
        if positionRounding ~= 0 then
            mainpos.x = math.Round(mainpos.x * positionRounding) / positionRounding
            mainpos.y = math.Round(mainpos.y * positionRounding) / positionRounding
            mainpos.z = math.Round(mainpos.z * positionRounding) / positionRounding
        end
    end
    return mainpos
end

function ENT:ManageProjectedTextures(position, angle, spreadEnabled, spreadSamples, pitch, sizeScale,debugCascade)
    if not self.ProjectedTextures[1] and not perfMode then
        self:createlamps()
    end
    
    -- Set Orthographic settings
    self.ProjectedTextures[1]:SetOrthographic(true, self:GetSizeNear() * sizeScale, self:GetSizeNear() * sizeScale, self:GetSizeNear() * sizeScale, self:GetSizeNear() * sizeScale)
    self.ProjectedTextures[2]:SetOrthographic(true, self:GetSizeMid() * sizeScale, self:GetSizeMid() * sizeScale, self:GetSizeMid() * sizeScale, self:GetSizeMid() * sizeScale)
    self.ProjectedTextures[3]:SetOrthographic(true, self:GetSizeFar() * sizeScale, self:GetSizeFar() * sizeScale, self:GetSizeFar() * sizeScale, self:GetSizeFar() * sizeScale)
    
    if furtherEnabled and self.ProjectedTextures[4] and self.ProjectedTextures[4]:IsValid() then
        self.ProjectedTextures[4]:SetOrthographic(true, self:GetSizeFurther() * sizescale, self:GetSizeFurther() * sizeScale, self:GetSizeFurther() * sizeScale, self:GetSizeFurther() * sizeScale)
    end
    
    -- Iterate over Projected Textures
	-- We should probably pass these values to the function rather than searching here.
	local depthBias = GetConVar("csm_depthbias"):GetFloat()
    local distanceBias = GetConVar("csm_depthbias_distancescale"):GetFloat()
    local slopeScaleDepthBias = GetConVar("csm_depthbias_slopescale"):GetFloat()
    self:UpdateProjectedTexturesSettings(position, angle, spreadEnabled, spreadSamples, pitch, debugCascade, depthBias, distanceBias, slopeScaleDepthBias)
end


function ENT:UpdateProjectedTexturesSettings(position, angle, spreadEnabled, spreadSamples, pitch, debugCascade, depthBias, distanceBias, slopeScaleDepthBias)
    local sunBright = (self:GetSunBrightness()) / 400

    if GetConVar("csm_stormfoxsupport"):GetInt() == 1 then
        self.CurrentAppearance = CalculateAppearance((pitch + -180) / 360)
        sunBright = (sunBright * self.CurrentAppearance.SunBrightness) * GetConVar("csm_stormfox_brightness_multiplier"):GetFloat()
        sunBright = (GetConVar("csm_hashdr"):GetInt() == 1) and sunBright * 1 or sunBright * 0.2
    end

    local debugColours = {}
    debugColours[1] = Color(0, 255, 0, 255)
    debugColours[2] = Color(255, 0, 0, 255)
    debugColours[3] = Color(255, 255, 0, 255)
    debugColours[4] = Color(0, 0, 255, 255)
    debugColours[5] = Color(0, 255, 255, 255)
    debugColours[6] = Color(255, 0, 255, 255)
    debugColours[7] = Color(255, 255, 255, 255)
    
    for i, projectedTexture in pairs(self.ProjectedTextures) do
        -- Set brightness and position
        self:SetProjectedTextureBrightness(projectedTexture, sunBright, spreadEnabled, spreadSamples, i)
        projectedTexture:SetPos(position)
        projectedTexture:SetAngles(angle)

        -- Apply debug colors if debugCascade is true
        if debugCascade then
            projectedTexture:SetColor(debugColours[i] or Color(255, 255, 255, 255))  -- Default to white if out of range
        elseif GetConVar("csm_stormfox_coloured_sun"):GetBool() then
            self.CurrentAppearance = CalculateAppearance((pitch + -180) / 360)
            projectedTexture:SetColor(self.CurrentAppearance.SunColour)
        else
            projectedTexture:SetColor(self:GetSunColour():ToColor())
        end
        
        -- Set shadow bias and filter
        local depthdistscale = distanceBias * (i - 1)
        projectedTexture:SetShadowDepthBias(depthBias + depthdistscale)
        projectedTexture:SetShadowSlopeScaleDepthBias(slopeScaleDepthBias)
        
        local filtscale = 1
        if GetConVar("csm_filter_distancescale"):GetBool() and ((i <= 3) or (i > 4)) then
            local distance = (i > 4) and 1 or i
            filtscale = 8^(distance - 1)
        end
        projectedTexture:SetShadowFilter(GetConVar("csm_filter"):GetFloat() / filtscale)

        projectedTexture:SetNearZ(self:GetSunNearZ())
        projectedTexture:SetFarZ(self:GetSunFarZ() * 1.025)
        projectedTexture:SetQuadraticAttenuation(0)
        projectedTexture:SetLinearAttenuation(0)
        projectedTexture:SetConstantAttenuation(1)
        projectedTexture:Update()
    end
end

function ENT:SetProjectedTextureBrightness(projectedTexture, sunBright, spreadEnabled, spreadSamples, i)
    if spreadEnabled then
        if i == 1 or i == 2 or i > 4 then
            projectedTexture:SetBrightness(sunBright / spreadSamples)
        else
            projectedTexture:SetBrightness(sunBright)
        end
    else
        projectedTexture:SetBrightness(sunBright)
    end
end

function ENT:UpdateSkyFogEffects(direction)
    if IsValid(self.EnvSun) then
        self.EnvSun:SetKeyValue("sun_dir", tostring(direction))
    end

    if IsValid(self.EnvSkyPaint) then
        self.EnvSkyPaint:SetKeyValue("TopColor", tostring(self.CurrentAppearance.SkyTopColor))
        self.EnvSkyPaint:SetKeyValue("BottomColor", tostring(self.CurrentAppearance.SkyBottomColor))
        self.EnvSkyPaint:SetKeyValue("DuskColor", tostring(self.CurrentAppearance.SkyDuskColor))
        self.EnvSkyPaint:SetKeyValue("SunColor", tostring(self.CurrentAppearance.SkySunColor))
    end

    if IsValid(self.EnvFogController) then
        self.EnvFogController:SetKeyValue("fogcolor", tostring(self.CurrentAppearance.FogColor))
    end
end

function ENT:Think()
    local csmEnabled = GetConVar("csm_enabled"):GetBool()
    local csmWakeProps = GetConVar("csm_wakeprops"):GetBool()
    local csmSpreadEnabled = GetConVar("csm_spread"):GetBool()
    local csmPerfMode = GetConVar("csm_perfmode"):GetBool()
    local csmFurtherShadows = GetConVar("csm_furthershadows"):GetBool()
    local csmFarShadows = GetConVar("csm_farshadows"):GetBool()
    local csmNoFar = GetConVar("csm_nofar"):GetBool()
    local csmSpreadSamples = GetConVar("csm_spread_samples"):GetInt()
    local csmPropRadiosity = GetConVar("csm_propradiosity"):GetString()
    local fpShadows = GetConVar("csm_localplayershadow"):GetBool()
    local harshCutoff = GetConVar("csm_harshcutoff"):GetBool()
    local furtherEnabled = GetConVar("csm_further"):GetBool()
    local blobShadows = GetConVar("csm_blobbyao"):GetBool()
    local sizeScale = GetConVar("csm_sizescale"):GetFloat()
	local debugCascade = GetConVar("csm_debug_cascade"):GetBool()
	local posRounding = GetConVar("csm_experimental_positionrounding"):GetFloat()

    -- Manage enabling/disabling CSM
    self:ManageCSMState(csmEnabled, csmWakeProps, csmPropRadiosity)
    
    -- Update radiosity if needed
    self:UpdateRadiosityIfNeeded(csmEnabled, csmPropRadiosity, csmWakeProps)
    
    -- Skip processing if CSM is disabled
    if not csmEnabled then return end
    
    -- Consolidated CLIENT code block
    if CLIENT then
		local sun = util.GetSunInfo()
        self:ManageFPSController(fpShadows)
        self:ManageFurtherShadows(furtherEnabled, harshCutoff, csmFurtherShadows)
        self:ManageFarShadows(csmFarShadows, csmNoFar)
        self:HandleSpreadSamples(csmSpreadSamples)
        self:UpdateSpreadLayersAndRadius()
        self:ManageSunEffects(csmPropRadiosity, csmWakeProps)
        self:ManageRTTShadows(blobShadows)
        self:ManageBlobShadows(csmEnabled, blobShadows)
		
        -- Calculate sun angles and offsets
        local pitch, yaw, roll = self:CalculateSunAngles()
        local offset, offset2 = self:CalculateOffsets(pitch, yaw, roll, usemapangles)
        local mainpos = self:CalculateMainPos(posRounding)
        local position = mainpos + offset * self:GetHeight()
        local angle = (usemapangles and vector_origin - offset2 or vector_origin - offset):Angle()
        
        -- Manage Projected Textures
		self:ManageProjectedTextures(position, angle, csmSpreadEnabled, csmSpreadSamples, pitch, sizeScale, debugCascade)

        -- Handle Sky and Fog effects
        if self:GetUseSkyFogEffects() then
            self:UpdateSkyFogEffects(offset)
        end
    end
end

function ENT:allocLights()
    local spreadLayers = GetConVar("csm_spread_layers"):GetInt()
    local spreadSamples = GetConVar("csm_spread_samples"):GetInt()
    local layerDensity = GetConVar("csm_spread_layer_density"):GetFloat()
    local spreadRadius = GetConVar("csm_spread_radius"):GetFloat()
    local reserveMiddle = GetConVar("csm_spread_layer_reservemiddle"):GetBool()
    local allocType = GetConVar("csm_spread_layer_alloctype"):GetInt()

    lightAlloc = {}
    lightPoints = {}

    -- Calculate initial allocation of lights for each layer
    self:allocateInitialLights(spreadLayers, spreadSamples)

    -- Adjust allocation to ensure total sum matches spreadSamples
    self:adjustLightAllocation(spreadLayers, spreadSamples)

    -- Apply specific allocation logic based on allocation type
    self:applyAllocationTypeLogic(spreadLayers, allocType)

    -- Calculate positions for each light
    self:calculateLightPositions(spreadLayers, spreadRadius, layerDensity, reserveMiddle)
end

--- Allocates initial lights for each layer based on the total number of samples and layers.
-- This function divides the number of samples (`spreadSamples`) among the number of layers (`spreadLayers`).
-- The first layer gets a ceiling value, and subsequent layers get a floor value to balance the distribution.
function ENT:allocateInitialLights(spreadLayers, spreadSamples)
    for i = 1, spreadLayers do
        local lightsPerLayer = (spreadSamples / spreadLayers)
        if i == 1 then
            lightsPerLayer = math.ceil(lightsPerLayer)
        else
            lightsPerLayer = math.floor(lightsPerLayer)
        end
        lightAlloc[i] = lightsPerLayer
    end
end

--- Adjusts the allocation of lights to ensure that the total matches the required number of samples.
-- This function checks if the sum of allocated lights matches `spreadSamples`. If not, it adjusts the allocation.
-- It attempts a maximum of 2 times to balance the distribution.
function ENT:adjustLightAllocation(spreadLayers, spreadSamples)
    local sum, attempts = 0, 0
    while sum ~= spreadSamples and attempts < 2 do
        attempts = attempts + 1
        sum = 0
        for _, count in ipairs(lightAlloc) do
            sum = sum + count
        end

        if sum > spreadSamples then
            lightAlloc[spreadLayers] = lightAlloc[spreadLayers] - 1
        elseif sum < spreadSamples then
            lightAlloc[attempts] = lightAlloc[attempts] + 1
        end
    end
end

--- Applies specific allocation logic to the light layers based on the allocation type.
-- Different allocation types (`allocType`) change the way lights are distributed among the layers.
-- If `allocType` is 1, the distribution is adjusted to reduce the number of lights in higher layers.
-- If not, it performs additional adjustments based on the provided conditions.
function ENT:applyAllocationTypeLogic(spreadLayers, allocType)
    if allocType == 1 and spreadLayers > 2 then
        for k = 1, spreadLayers do
            if lightAlloc[k] > 2 then
                lightAlloc[k] = lightAlloc[k] - (k - 2)
            end
        end
    elseif spreadLayers > 1 and lightAlloc[spreadLayers] > 3 then
        lightAlloc[spreadLayers] = lightAlloc[spreadLayers] - 1
        lightAlloc[1] = lightAlloc[1] + 1
    end

    if lightAlloc[spreadLayers] > 3 and spreadLayers > 1 and GetConVar("csm_spread_layer_reservemiddle"):GetBool() then
        lightAlloc[spreadLayers] = lightAlloc[spreadLayers] - 1
    end
end

--- Calculates the positions for each light around a circle for each layer.
-- This function distributes lights around a circle for each layer based on the allocated lights and spread radius.
-- It also handles reserving a middle position for the lights if `reserveMiddle` is set to true.
function ENT:calculateLightPositions(spreadLayers, spreadRadius, layerDensity, reserveMiddle)
    for i = 1, spreadLayers do
        local lightsPerLayer = lightAlloc[i]
        local layerRadius = ((spreadLayers - (i - 1)) - ((layerDensity * -1) * (i - 1))) / spreadLayers * spreadRadius
        
        for degrees = 1, 360, 360 / lightsPerLayer do
            local x, y = PointOnCircle(degrees, layerRadius, 0, 0)
            table.insert(lightPoints, Angle(x, y, 0))
        end

        if spreadLayers > 1 and lightsPerLayer > 1 and i == spreadLayers and reserveMiddle then
            table.insert(lightPoints, Angle(0, 0, 0))
        end
    end
end

--- Computes a point's X and Y coordinates on a circle's circumference.
-- Given an angle and radius, this function calculates the point's position on the circle.
function PointOnCircle(angle, radius, offsetX, offsetY)
	angle = math.rad(angle)
	local x = math.cos(angle) * radius + offsetX
	local y = math.sin(angle) * radius + offsetY
	return x, y
end

--- Calculates the appearance of an entity based on its position between two key points.
-- This function interpolates values between two keys to find the appearance at a given position.
-- If the position exactly matches a key, that key is returned directly.
function CalculateAppearance(position)
	local from, to

	for i, key in pairs(AppearanceKeys) do
		if (key.Position == position) then
			return key
		end

		if (key.Position < position) then
			from = key
		end

		if (key.Position > position) then
			to = key
			break
		end
	end

	if from == nil then
		from = AppearanceKeys[#AppearanceKeys]
	end

	if to == nil then
		to = AppearanceKeys[1]
	end

	local t = (position - from.Position) / (to.Position - from.Position)
	local result = { }

	for i, key in pairs(from) do
		if type(key) == "table" then
			result[i] = LerpColor(t, from[i], to[i])
		else
			result[i] = Lerp(t, from[i], to[i])
		end
	end

	return result
end

function LerpColor(t, fromColor, toColor)
	local r = Lerp(t, fromColor.r, toColor.r)
	local g = Lerp(t, fromColor.g, toColor.g)
	local b = Lerp(t, fromColor.b, toColor.b)
	local a = Lerp(t, fromColor.a, toColor.a)

	return Color(r, g, b, a)
end

function FindEntity(class)
	local entities = ents.FindByClass(class)

	if (#entities > 0) then
		return entities[1]
	else
		return nil
	end
end
