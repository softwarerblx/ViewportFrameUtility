--!strict

--[[
	Name: ViewportFrameUtility
	Description: A strictly-typed utility class for displaying models in ViewportFrames
	Additional Credits: EgoMoose for the model fitting math
	Author: Developing_Maniac
]]

local RunService = game:GetService("RunService")

local ViewportFrameUtility = {}
ViewportFrameUtility.__index = ViewportFrameUtility

type self = {
	Model: Model,
	Camera: Camera,
	ViewportFrame: ViewportFrame,
	ModelCFrame: CFrame,
	StartCFrame: CFrame,
	ModelSize: Vector3,
	DragStartPosition: Vector3,
	Delta: Vector2,
	ModelRadius: number,
	ZoomOffset: number,
	xRotation: number,
	ViewportData: {[string]: any},
	IsLerping: boolean,
	IsDragging: boolean,
	IsOrbiting: boolean,

	GetFitDistance: () -> (number),
	FitModel: () -> (),
	ResetCamera: () -> (),
	Calibrate: () -> (),
	ToggleAnimation: (state: boolean) -> (),
	ToggleDragging: (state: boolean) -> (),
	ToggleZooming: (state: boolean) -> (),
	ToggleOrbiting: (state: boolean) -> (),

	InputBeganConnection: RBXScriptConnection?,
	InputChangedConnection: RBXScriptConnection?,
	InputEndedConnection: RBXScriptConnection?,
	RenderSteppedConnection: RBXScriptConnection?,
	ZoomConnection: RBXScriptConnection?,
}

type ViewportFrameUtility = typeof(setmetatable({}, ViewportFrameUtility))

--[[
	Creates a new instance of the utility class

	@param viewportFrame The viewport frame to display the model in
	@param model The model to display in the viewport frame
	@return A new instance of ViewportFrameUtility
]]

function ViewportFrameUtility.new(viewportFrame: ViewportFrame, model: Model): any
	local cframe: CFrame, size: Vector3 = model:GetBoundingBox()

	local self = setmetatable({}, ViewportFrameUtility)

	self.Model = model:Clone()
	self.Model.Parent = viewportFrame
	self.Camera = Instance.new("Camera")
	self.Camera.Parent = viewportFrame
	self.ViewportFrame = viewportFrame
	self.ViewportFrame.CurrentCamera = self.Camera
	self.ModelCFrame = cframe
	self.ModelSize = size
	self.ModelRadius = size.Magnitude / 2
	self.ViewportData = {}
	self.ZoomOffset = 0
	self.xRotation = 0
	self.Delta = Vector2.new()
	self.DragStartPosition = Vector3.new()

	self:Calibrate()

	return self
end

-- Calibrates some values based on the ViewportFrame's size and aspect ratio

function ViewportFrameUtility:Calibrate(): ()
	local viewport = {}
	local size = self.ViewportFrame.AbsoluteSize

	viewport.Aspect = size.X / size.Y

	viewport.yFov2 = math.rad(self.Camera.FieldOfView / 2)
	viewport.TanYFov2 = math.tan(viewport.yFov2)

	viewport.xFov2 = math.atan(viewport.TanYFov2 * viewport.Aspect)
	viewport.TanXFov2 = math.tan(viewport.xFov2)

	viewport.cFov2 = math.atan(viewport.TanYFov2 * math.min(1, viewport.Aspect))
	viewport.SinCFov2 = math.sin(viewport.cFov2)

	self.ViewportData = viewport
end

--[[
	Calculates and returns a distance between the camera and model that would fit it perfectly into the ViewportFrame

	@param focusPosition An optional position vector that can be used as a focal point for fitting (default is nil)
	@return A number representing the distance between the Camera and Model that would fit it perfectly into the ViewportFrame
]]

function ViewportFrameUtility:GetFitDistance(focusPosition: Vector3): number
	local displacement = focusPosition and (focusPosition - self.ModelCFrame.Position).Magnitude or 0
	local radius = self.ModelRadius + displacement

	return radius / self.ViewportData.SinCFov2
end

-- Fits the Model into the ViewportFrame by setting the Camera's CFrame relative to the Model's CFrame

function ViewportFrameUtility:FitModel(): ()
	local camera = self.Camera
	local cframe, size = self.Model:GetBoundingBox()

	self.Model:PivotTo(self.Model:GetPivot() * CFrame.Angles(0, math.rad(180), 0))

	camera.CFrame = cframe * CFrame.new(0, 0, self:GetFitDistance(self.Model:GetPivot().Position))

	self.StartCFrame = camera.CFrame:Orthonormalize()
end

-- Resets the camera to its original position

function ViewportFrameUtility:ResetCamera(): ()
	self.IsLerping = true

	local speed = 0.1

	while (self.Camera.CFrame.Position - self.StartCFrame.Position).Magnitude > 0.01 do
		self.Camera.CFrame = self.Camera.CFrame:Lerp(self.StartCFrame, speed)

		task.wait()
	end

	self.IsLerping = false
end

--[[
	Enables or disables zooming on the ViewportFrame to zoom in and out of the model

	@param state A boolean value indicating whether to enable or disable zooming
]]

function ViewportFrameUtility:ToggleZooming(state: boolean): ()
	if not state then
		if self.ZoomConnection then
			self.ZoomConnection:Disconnect()
			self.ZoomConnection = nil
		end

		return
	end

	local camera = self.Camera

	local minimumZoomDistance = 5
	local maximumZoomDistance = 10

	self.ZoomConnection = self.ViewportFrame.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local zoomDistance = (camera.CFrame.Position - self.Model:GetPivot().Position).Magnitude

			if input.Position.Z > 0 and zoomDistance > minimumZoomDistance then
				self.ZoomOffset = math.clamp(self.ZoomOffset - 1, -2, 5)
			elseif input.Position.Z < 0 and zoomDistance < maximumZoomDistance then
				self.ZoomOffset = math.clamp(self.ZoomOffset + 1, -2, 5)
			end
		end
	end)
end

--[[
	Enables or disables dragging on the ViewportFrame to rotate the camera around the model

	@param state A boolean value indicating whether dragging should be enabled or disabled
]]

function ViewportFrameUtility:ToggleDragging(state: boolean): ()
	if not state then
		if self.InputBeganConnection then
			self.InputBeganConnection:Disconnect()
			self.InputBeganConnection = nil
		end

		if self.InputChangedConnection then
			self.InputChangedConnection:Disconnect()
			self.InputChangedConnection = nil
		end

		if self.InputEndedConnection then
			self.InputEndedConnection:Disconnect()
			self.InputEndedConnection = nil
		end
	end

	local function updateInput(input: InputObject): ()
		if self.IsDragging then
			self.Delta = input.Position - self.DragStartPosition
			self.xRotation = math.clamp(-self.Delta.Y / 100, -math.pi / 2, math.pi / 2)
		end
	end

	self.InputBeganConnection = self.ViewportFrame.InputBegan:Connect(function(input: InputObject)
		if self.IsLerping then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.IsDragging = true
			self.DragStartPosition = input.Position
		end

		updateInput(input)
	end)

	self.InputChangedConnection = self.ViewportFrame.InputChanged:Connect(updateInput)

	self.InputEndedConnection = self.ViewportFrame.InputEnded:Connect(function(input: InputObject)
		if self.IsLerping then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.IsDragging = false
		end

		updateInput(input)
	end)
end

--[[
	Enables or disables automatic orbiting of the camera around the model

	@param state A boolean value indicating whether automatic orbiting should be enabled or disabled
]]

function ViewportFrameUtility:ToggleOrbiting(state: boolean): ()
	self.IsOrbiting = state
end

--[[
	Enables or disables animation on the ViewportFrame to animate the camera

	@param state A boolean value indicating whether dragging should be enabled or disabled
]]

function ViewportFrameUtility:ToggleAnimation(state: boolean): ()
	if not state then
		if self.RenderSteppedConnection then
			self.RenderSteppedConnection:Disconnect()
			self.RenderSteppedConnection = nil
		end

		return
	end

	local function updateDt(deltaTime: number)
		local camera = self.Camera
		local delta = self.Delta
		local xRotation = self.xRotation
		local isDragging = self.IsDragging

		if isDragging then
			local targetCFrame = CFrame.new(self.Model:GetPivot().Position) *
				CFrame.Angles(0, -delta.X / 100, 0) *
				CFrame.Angles(xRotation, 0, 0) *
				CFrame.new(-self.Model:GetPivot().Position) *
				CFrame.new(0, 0, self.ZoomOffset) *
				self.StartCFrame
			local interpolationFactor = math.min(1, math.max(0, 6 * deltaTime))

			camera.CFrame = camera.CFrame:Lerp(targetCFrame, interpolationFactor)
		else
			local orbiting = self.IsOrbiting

			if orbiting then
				local pivotPosition = self.Model:GetPivot().Position
				local targetCFrame = CFrame.new(pivotPosition) *
					CFrame.Angles(0, deltaTime * math.pi / 2, 0) *
					CFrame.new(-pivotPosition) *
					camera.CFrame

				camera.CFrame = targetCFrame
			else
				local targetCFrame = self.StartCFrame * CFrame.new(0, 0, self.ZoomOffset)
				local interpolationFactor = math.min(1, math.max(0, 6 * deltaTime))

				camera.CFrame = camera.CFrame:Lerp(targetCFrame, interpolationFactor)
			end
		end
	end

	self.RenderSteppedConnection = RunService.RenderStepped:Connect(updateDt)
end

return ViewportFrameUtility