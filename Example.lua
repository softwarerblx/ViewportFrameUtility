local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Replace this with your path to the ViewportFrameUtility module
local ViewportFrameUtility = require(ReplicatedStorage.ViewportFrameUtility)

-- Replace this with your ViewportFrame
local viewportFrame = script.Parent.ViewportFrame

-- Replace this with your model
local viewportFrameUtility = ViewportFrameUtility.new(viewportFrame, workspace.Dummy)

-- Makes the model fit in the viewport frame
viewportFrameUtility:FitModel()

-- Enables animation for the ViewportFrame
viewportFrameUtility:EnableAnimation()

-- Enables dragging for the ViewportFrame
viewportFrameUtility:EnableDragging()

-- Enables zooming for the ViewportFrame
viewportFrameUtility:EnableZooming()

-- Enables orbiting for the ViewportFrame
viewportFrameUtility:EnableOrbiting()