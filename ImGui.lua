--// Written by depso
--// MIT License
--// Copyright (c) 2024 Depso
--//
--// Maintained fork of Depso's Roblox ImGui (the original project is discontinued).
--// Changes in this fork:
--//  * Built-in UI prefabs, used automatically when the original asset can't be loaded
--//  * Touch / mobile support (drag, resize, sliders, dropdowns, keybinds, window focus)
--//  * Optional UIScale for touch-only devices + windows are kept on screen
--//  * Bug fixes (see the notes next to each change marked with "FIX")

local ImGui = {
	Animations = {
		Buttons = {
			MouseEnter = {
				BackgroundTransparency = 0.5,
			},
			MouseLeave = {
				BackgroundTransparency = 0.7,
			} 
		},
		Tabs = {
			MouseEnter = {
				BackgroundTransparency = 0.5,
			},
			MouseLeave = {
				BackgroundTransparency = 1,
			} 
		},
		Inputs = {
			MouseEnter = {
				BackgroundTransparency = 0,
			},
			MouseLeave = {
				BackgroundTransparency = 0.5,
			} 
		},
		WindowBorder = {
			Selected = {
				Transparency = 0,
				Thickness = 1
			},
			Deselected = {
				Transparency = 0.7,
				Thickness = 1
			}
		},
	},

	Windows = {},
	Animation = TweenInfo.new(0.1),
	UIAssetId = "rbxassetid://76246418997296",

	--// Mobile / touch
	TouchScale = 1.2, --// Window scale used on touch-only devices (set to 1 to disable)
	Scale = 1,
	ClampToScreen = true --// Keep windows inside the screen
}


--// Universal functions
local NullFunction = function() end
local CloneRef = cloneref or function(_)return _ end
local function GetService(...)
	return CloneRef(game:GetService(...))
end

function ImGui:Warn(...)
	if self.NoWarnings then return end
	return warn("[IMGUI]", ...)
end

--// Services 
local TweenService: TweenService = GetService("TweenService")
local UserInputService: UserInputService = GetService("UserInputService")
local Players: Players = GetService("Players")
local CoreGui = GetService("CoreGui")
local RunService: RunService = GetService("RunService")

--// LocalPlayer
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--// ImGui Config
local IsStudio = RunService:IsStudio()
ImGui.NoWarnings = not IsStudio

--// Touch-only devices (phones/tablets without a keyboard) get a bigger UI
ImGui.IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
ImGui.Scale = ImGui.IsMobile and ImGui.TouchScale or 1

--// Input helpers
local MouseButton1 = Enum.UserInputType.MouseButton1
local MouseMovement = Enum.UserInputType.MouseMovement
local Touch = Enum.UserInputType.Touch

local function IsPointerStart(Input: InputObject): boolean
	local Type = Input.UserInputType
	return Type == MouseButton1 or Type == Touch
end

local function IsPointInside(GuiObject: GuiObject, Position: Vector3 | Vector2): boolean
	local Pos = GuiObject.AbsolutePosition
	local Size = GuiObject.AbsoluteSize
	return Position.X >= Pos.X and Position.X <= Pos.X + Size.X
		and Position.Y >= Pos.Y and Position.Y <= Pos.Y + Size.Y
end

--// Scale / screen helpers
function ImGui:GetScale(): number
	return self.Scale or 1
end

function ImGui:GetViewportSize(): Vector2
	local Gui = self.ScreenGui
	local Size = Gui and Gui.AbsoluteSize or Vector2.zero

	if Size.X <= 0 or Size.Y <= 0 then
		local Camera = workspace.CurrentCamera
		Size = Camera and Camera.ViewportSize or Vector2.new(1280, 720)
	end
	return Size
end

--// Make sure a window size never exceeds the screen (phones are small!)
function ImGui:ClampSizeToScreen(Size: UDim2): UDim2
	if not self.ClampToScreen then return Size end

	local Viewport = self:GetViewportSize()
	local Scale = self:GetScale()
	local MaxX = math.floor(Viewport.X * 0.96 / Scale)
	local MaxY = math.floor(Viewport.Y * 0.92 / Scale)

	local X, Y = Size.X, Size.Y
	if X.Scale == 0 and X.Offset > MaxX then X = UDim.new(0, MaxX) end
	if Y.Scale == 0 and Y.Offset > MaxY then Y = UDim.new(0, MaxY) end

	return UDim2.new(X, Y)
end

--// Keep a part of the window reachable so it can't get lost off screen
function ImGui:ClampWindowPosition(Window: GuiObject)
	if not self.ClampToScreen then return end
	if not Window or not Window.Parent or Window.Parent ~= self.ScreenGui then return end

	local Viewport = self:GetViewportSize()
	local Pos = Window.AbsolutePosition
	local Size = Window.AbsoluteSize
	local Keep = 48 --// Pixels that must stay visible

	local TargetX = math.clamp(Pos.X, Keep - Size.X, Viewport.X - Keep)
	local TargetY = math.clamp(Pos.Y, 0, Viewport.Y - Keep)
	local DeltaX, DeltaY = TargetX - Pos.X, TargetY - Pos.Y
	if DeltaX == 0 and DeltaY == 0 then return end

	local Current = Window.Position
	Window.Position = UDim2.new(
		Current.X.Scale, Current.X.Offset + DeltaX,
		Current.Y.Scale, Current.Y.Offset + DeltaY
	)
end

function ImGui:SetScale(Scale: number)
	Scale = math.clamp(tonumber(Scale) or 1, 0.5, 3)
	self.Scale = Scale

	for Window in next, self.Windows do
		local UIScale = Window:FindFirstChildOfClass("UIScale")
		if UIScale then
			UIScale.Scale = Scale
		end
	end
	return self
end

--// Built-in prefabs 
--// Used when the original asset can't be loaded (deleted, GetObjects unsupported, ...)
--// The hierarchy/names match what the rest of this file expects.
function ImGui:BuildFallbackUI()
	local Theme = {
		WindowBg = Color3.fromRGB(15, 15, 15),
		TitleBg = Color3.fromRGB(41, 74, 122),
		Frame = Color3.fromRGB(66, 150, 250),
		FrameDark = Color3.fromRGB(41, 74, 122),
		Grab = Color3.fromRGB(61, 133, 224),
		Border = Color3.fromRGB(110, 110, 128),
		Text = Color3.fromRGB(255, 255, 255),
		TextDim = Color3.fromRGB(140, 140, 140),
		Font = Enum.Font.Code,
		TextSize = 14
	}

	local function New(ClassName: string, Properties, Children)
		local Object = Instance.new(ClassName)
		local Parent = nil

		for Key, Value in next, Properties or {} do
			if Key == "Parent" then
				Parent = Value
			else
				Object[Key] = Value
			end
		end
		for _, Child in next, Children or {} do
			Child.Parent = Object
		end

		Object.Parent = Parent
		return Object
	end

	--// Frame/Text constructors with shared defaults
	local function Box(ClassName: string, Properties, Children)
		local Props = {
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
		}
		for Key, Value in next, Properties or {} do
			Props[Key] = Value
		end
		return New(ClassName, Props, Children)
	end

	local function Text(ClassName: string, Properties, Children)
		local Props = {
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			Font = Theme.Font,
			TextSize = Theme.TextSize,
			TextColor3 = Theme.Text,
		}
		if ClassName == "TextButton" then
			Props.AutoButtonColor = false
			Props.Text = ""
		end
		for Key, Value in next, Properties or {} do
			Props[Key] = Value
		end
		return New(ClassName, Props, Children)
	end

	local function Padding(Left: number, Top: number?, Right: number?, Bottom: number?)
		Top = Top or Left
		return New("UIPadding", {
			PaddingLeft = UDim.new(0, Left),
			PaddingTop = UDim.new(0, Top),
			PaddingRight = UDim.new(0, Right or Left),
			PaddingBottom = UDim.new(0, Bottom or Top),
		})
	end

	local function Corner(Radius: UDim | number)
		return New("UICorner", {
			CornerRadius = typeof(Radius) == "UDim" and Radius or UDim.new(0, Radius)
		})
	end

	local function Stroke(Enabled: boolean?)
		return New("UIStroke", {
			Color = Theme.Border,
			Thickness = 1,
			Transparency = 0.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Enabled = Enabled ~= false
		})
	end

	local function List(PaddingPx: number?, Horizontal: boolean?, Center: boolean?)
		return New("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, PaddingPx or 0),
			FillDirection = Horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
			VerticalAlignment = Center and Enum.VerticalAlignment.Center or Enum.VerticalAlignment.Top
		})
	end

	local function Gradient()
		return New("UIGradient", {Enabled = false})
	end

	--// Arrow used by windows, headers and combos (rotates 90 when open)
	local function Arrow(LayoutOrder: number?)
		return Box("Frame", {
			Name = "Toggle",
			LayoutOrder = LayoutOrder or 1,
			Size = UDim2.fromOffset(22, 22),
		}, {
			Box("ImageButton", {
				Name = "ToggleButton",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Theme.Frame,
				AutoButtonColor = false,
			}, {
				Corner(4),
				Text("TextLabel", {
					Name = "Arrow",
					Text = ">",
					TextSize = 13,
					Size = UDim2.fromScale(1, 1),
				})
			})
		})
	end

	--// Prefabs
	local Prefabs = Box("Frame", {Name = "Prefabs", Visible = false})

	local function Add(Prefab: Instance)
		Prefab.Parent = Prefabs
		return Prefab
	end

	--// Window
	Add(Box("Frame", {
		Name = "Window",
		Size = UDim2.fromOffset(300, 200),
		Position = UDim2.fromOffset(60, 60),
		BackgroundColor3 = Theme.WindowBg,
		BackgroundTransparency = 0.05,
		ClipsDescendants = true,
		Visible = false,
	}, {
		Stroke(),
		Corner(4),
		Box("Frame", {
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
		}, {
			List(0),
			Box("Frame", {
				Name = "TitleBar",
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundColor3 = Theme.TitleBg,
				BackgroundTransparency = 0,
			}, {
				Box("Frame", {
					Name = "Left",
					Size = UDim2.new(1, -32, 1, 0),
				}, {
					List(4, true, true),
					Padding(4, 0, 0, 0),
					Arrow(1),
					Text("TextLabel", {
						Name = "Title",
						LayoutOrder = 2,
						Text = "Window",
						AutomaticSize = Enum.AutomaticSize.XY,
						Size = UDim2.fromOffset(0, 0),
						TextXAlignment = Enum.TextXAlignment.Left,
					})
				}),
				Text("TextButton", {
					Name = "Close",
					Text = "X",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -3, 0.5, 0),
					Size = UDim2.fromOffset(24, 24),
					BackgroundColor3 = Theme.Frame,
				}, {
					Corner(4)
				})
			}),
			Box("ScrollingFrame", {
				Name = "ToolBar",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 28),
				ScrollBarThickness = 0,
				ScrollingDirection = Enum.ScrollingDirection.X,
				AutomaticCanvasSize = Enum.AutomaticSize.X,
				CanvasSize = UDim2.new(),
				ElasticBehavior = Enum.ElasticBehavior.Never,
			}, {
				List(2, true, true),
				Padding(4, 0, 4, 0),
				Text("TextButton", {
					Name = "TabButton",
					Visible = false,
					Text = "Tab",
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, 24),
					BackgroundColor3 = Theme.Frame,
				}, {
					Padding(10, 0, 10, 0),
					Corner(4),
				})
			}),
			Box("ScrollingFrame", {
				Name = "Body",
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 1, -56),
				ScrollBarThickness = 6,
				ScrollBarImageColor3 = Theme.Border,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				ElasticBehavior = Enum.ElasticBehavior.Never,
			}, {
				--// Tab page template (cloned by CreateTab)
				Box("Frame", {
					Name = "Template",
					Visible = false,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
				}, {
					List(4),
					Padding(8)
				})
			})
		}),
		Text("TextButton", {
			Name = "ResizeGrab",
			Text = "◢",
			TextSize = 14,
			TextTransparency = 0.6,
			ZIndex = 10,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
			Size = UDim2.fromOffset(24, 24),
		})
	}))

	--// Button
	Add(Text("TextButton", {
		Name = "Button",
		Text = "Button",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		BackgroundColor3 = Theme.Frame,
		BackgroundTransparency = 0.7,
	}, {
		Padding(10, 0, 10, 0),
		Corner(3),
		Stroke(false),
		Gradient(),
	}))

	--// Image
	Add(Text("ImageButton", {
		Name = "Image",
		Size = UDim2.fromOffset(50, 50),
		BackgroundColor3 = Theme.Frame,
		BackgroundTransparency = 0.7,
		AutoButtonColor = false,
	}, {
		Corner(3),
		Stroke(false),
		Gradient(),
	}))

	--// ScrollBox
	Add(Box("ScrollingFrame", {
		Name = "ScrollBox",
		Size = UDim2.new(1, 0, 0, 200),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Border,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, {
		List(4),
		Padding(6),
		Stroke(),
	}))

	--// Label
	Add(Text("TextLabel", {
		Name = "Label",
		Text = "Label",
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	}))

	--// CheckBox / RadioButton
	Add(Text("TextButton", {
		Name = "CheckBox",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
	}, {
		List(6, true, true),
		Text("ImageButton", {
			Name = "Tickbox",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = Theme.Frame,
			BackgroundTransparency = 0.7,
			ClipsDescendants = true,
		}, {
			Padding(4),
			Corner(UDim.new(1, 0)),
			Box("ImageLabel", {
				Name = "Tick",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0, 0),
				BackgroundColor3 = Theme.Grab,
				BackgroundTransparency = 0,
			})
		}),
		Text("TextLabel", {
			Name = "Label",
			LayoutOrder = 2,
			Text = "CheckBox",
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	}))

	--// Viewport
	Add(Box("Frame", {
		Name = "Viewport",
		Size = UDim2.fromOffset(200, 200),
	}, {
		New("ViewportFrame", {
			Name = "Viewport",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
		}, {
			New("WorldModel", {Name = "WorldModel"})
		})
	}))

	--// TextInput
	Add(Box("Frame", {
		Name = "TextInput",
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = Theme.FrameDark,
		BackgroundTransparency = 0.5,
	}, {
		Corner(3),
		Text("TextBox", {
			Name = "Input",
			Size = UDim2.fromScale(1, 1),
			Text = "",
			PlaceholderColor3 = Theme.TextDim,
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClipsDescendants = true,
		}, {
			Padding(6, 0, 6, 0)
		}),
		Text("TextLabel", {
			Name = "Label",
			Text = "",
			TextColor3 = Theme.TextDim,
			AutomaticSize = Enum.AutomaticSize.XY,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(0, 0),
			Active = false,
		})
	}))

	--// Console
	Add(Box("ScrollingFrame", {
		Name = "Console",
		Size = UDim2.new(1, 0, 0, 200),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Border,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, {
		Text("TextLabel", {
			Name = "Lines",
			Visible = false,
			Text = "",
			TextColor3 = Theme.TextDim,
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Top,
		}, {
			Padding(4, 2, 4, 2)
		}),
		Text("TextBox", {
			Name = "Source",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = "",
			MultiLine = true,
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}, {
			Padding(4, 2, 4, 2)
		})
	}))

	--// Table
	Add(Box("Frame", {
		Name = "Table",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		List(2),
		Box("Frame", {
			Name = "RowTemp",
			Visible = false,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, {
			List(0, true),
			Box("Frame", {
				Name = "ColumnTemp",
				Visible = false,
				Size = UDim2.fromScale(0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			}, {
				List(4),
				Padding(4),
				Stroke(),
			})
		})
	}))

	--// CollapsingHeader / TreeNode
	Add(Box("Frame", {
		Name = "CollapsingHeader",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		List(0),
		Text("TextButton", {
			Name = "TitleBar",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = Theme.Frame,
			BackgroundTransparency = 0.7,
		}, {
			List(4, true, true),
			Padding(4, 0, 4, 0),
			Corner(3),
			Arrow(1),
			Text("TextLabel", {
				Name = "Title",
				LayoutOrder = 2,
				Text = "Header",
				AutomaticSize = Enum.AutomaticSize.XY,
				Size = UDim2.fromOffset(0, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		}),
		Box("Frame", {
			Name = "ChildContainer",
			LayoutOrder = 2,
			Size = UDim2.new(1, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, {
			List(4),
			Padding(0, 4, 0, 4),
		})
	}))

	--// SeparatorText
	Add(Box("Frame", {
		Name = "SeparatorText",
		Size = UDim2.new(1, 0, 0, 18),
	}, {
		Box("Frame", {
			Name = "Line",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Theme.Border,
			BackgroundTransparency = 0.5,
		}),
		Text("TextLabel", {
			Name = "TextLabel",
			Text = "",
			AutomaticSize = Enum.AutomaticSize.XY,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = Theme.WindowBg,
			BackgroundTransparency = 0,
		}, {
			Padding(4, 0, 4, 0)
		})
	}))

	--// Row
	Add(Box("Frame", {
		Name = "Row",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		List(4, true, true),
		Padding(0),
	}))

	--// Slider (label sits to the right of the bar)
	Add(Text("TextButton", {
		Name = "Slider",
		Size = UDim2.new(1, -120, 0, 24),
		BackgroundColor3 = Theme.FrameDark,
		BackgroundTransparency = 0.5,
	}, {
		Padding(10, 0, 10, 0),
		Corner(3),
		Box("Frame", {
			Name = "Grab",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(0, 10, 1, -4),
			BackgroundColor3 = Theme.Grab,
			BackgroundTransparency = 0,
		}, {
			Corner(3),
			Gradient(),
		}),
		Text("TextLabel", {
			Name = "ValueText",
			Text = "0",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
		}),
		Text("TextLabel", {
			Name = "Label",
			Text = "",
			Position = UDim2.new(1, 15, 0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	}))

	--// Keybind
	Add(Text("TextButton", {
		Name = "Keybind",
		Size = UDim2.new(1, -120, 0, 24),
		BackgroundColor3 = Theme.FrameDark,
		BackgroundTransparency = 0.5,
	}, {
		Corner(3),
		Text("TextLabel", {
			Name = "ValueText",
			Text = "Not set",
			Size = UDim2.fromScale(1, 1),
		}),
		Text("TextLabel", {
			Name = "Label",
			Text = "",
			Position = UDim2.new(1, 10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	}))

	--// Combo
	Add(Text("TextButton", {
		Name = "Combo",
		Size = UDim2.new(1, -120, 0, 24),
		BackgroundColor3 = Theme.FrameDark,
		BackgroundTransparency = 0.5,
	}, {
		Corner(3),
		Text("TextLabel", {
			Name = "ValueText",
			Text = "",
			Size = UDim2.new(1, -26, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, {
			Padding(8, 0, 0, 0)
		}),
		Box("Frame", {
			Name = "Toggle",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -1, 0.5, 0),
			Size = UDim2.fromOffset(22, 22),
		}, {
			Box("ImageButton", {
				Name = "ToggleButton",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Theme.Frame,
				AutoButtonColor = false,
			}, {
				Corner(3),
				Text("TextLabel", {
					Name = "Arrow",
					Text = ">",
					TextSize = 13,
					Size = UDim2.fromScale(1, 1),
				})
			})
		}),
		Text("TextLabel", {
			Name = "Label",
			Text = "",
			Position = UDim2.new(1, 10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	}))

	--// Selection (dropdown list for Combos)
	Add(Box("ScrollingFrame", {
		Name = "Selection",
		Size = UDim2.fromOffset(150, 100),
		BackgroundColor3 = Color3.fromRGB(20, 20, 20),
		BackgroundTransparency = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Border,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 50,
	}, {
		Stroke(),
		List(0),
		Text("TextButton", {
			Name = "Template",
			Text = "Item",
			ZIndex = 51,
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = Theme.Frame,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, {
			Padding(8, 0, 0, 0)
		})
	}))

	--// ModalEffect
	Add(Box("Frame", {
		Name = "ModalEffect",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		Active = true,
		Visible = false,
	}))

	return New("ScreenGui", {Name = "DepsoImGui"}, {Prefabs})
end

--// Prefabs 
local RequiredPrefabs = {
	"Window", "Button", "Image", "ScrollBox", "Label", "CheckBox", "Viewport",
	"TextInput", "Console", "Table", "CollapsingHeader", "SeparatorText", "Row",
	"Slider", "Keybind", "Combo", "Selection", "ModalEffect"
}

local function IsValidUI(UI): boolean
	if typeof(UI) ~= "Instance" then return false end

	local Prefabs = UI:FindFirstChild("Prefabs")
	if not Prefabs then return false end

	for _, Name in RequiredPrefabs do
		if not Prefabs:FindFirstChild(Name) then
			return false
		end
	end
	return true
end

function ImGui:FetchUI()
	--// Cache check 
	local CacheName = "DepsoImGui"
	if _G[CacheName] then
		self:Warn("Prefabs loaded from Cache")
		return _G[CacheName]
	end

	local UI = nil

	if IsStudio then
		--// Studio
		local UIName = "DepsoImGui"
		UI = PlayerGui:FindFirstChild(UIName)
		if not UI and typeof(script) == "Instance" then
			UI = script:FindFirstChild(UIName)
		end
	elseif not _G.ImGuiForceFallback then
		--// Universal: load the original asset
		--// FIX: the asset can be deleted or GetObjects can be unavailable, don't hard error
		local Success, Result = pcall(function()
			return game:GetObjects(ImGui.UIAssetId)[1]
		end)
		if Success and IsValidUI(Result) then
			UI = Result
		else
			self.NoWarnings = false
			self:Warn("Could not load the UI asset, using the built-in UI instead.")
		end
	end

	--// Built-in fallback
	if not IsValidUI(UI) then
		UI = self:BuildFallbackUI()
	end

	_G[CacheName] = UI
	return UI
end

local UI = ImGui:FetchUI()
local Prefabs = UI.Prefabs
ImGui.Prefabs = Prefabs
Prefabs.Visible = false

--// Styles
local AddionalStyles = {
	[{
		Name="Border"
	}] = function(GuiObject: GuiObject, Value, Class)
		local Outline = GuiObject:FindFirstChildOfClass("UIStroke")
		if not Outline then return end

		local BorderThickness = Class.BorderThickness
		if BorderThickness then
			Outline.Thickness = BorderThickness
		end

		Outline.Enabled = Value
	end,

	[{
		Name="Ratio"
	}] = function(GuiObject: GuiObject, Value, Class)
		local RatioAxis = Class.RatioAxis or "Height"
		local AspectRatio = Class.Ratio or 4/3
		local AspectType = Class.AspectType or Enum.AspectType.ScaleWithParentSize

		local Ratio = GuiObject:FindFirstChildOfClass("UIAspectRatioConstraint")
		if not Ratio then
			Ratio = ImGui:CreateInstance("UIAspectRatioConstraint", GuiObject)
		end

		Ratio.DominantAxis = Enum.DominantAxis[RatioAxis]
		Ratio.AspectType = AspectType
		Ratio.AspectRatio = AspectRatio
	end,

	[{
		Name="CornerRadius",
		Recursive=true
	}] = function(GuiObject: GuiObject, Value, Class)
		local UICorner = GuiObject:FindFirstChildOfClass("UICorner")
		if not UICorner then
			UICorner = ImGui:CreateInstance("UICorner", GuiObject)
		end

		UICorner.CornerRadius = Class.CornerRadius
	end,

	[{
		Name="Label"
	}] = function(GuiObject: GuiObject, Value, Class)
		local Label = GuiObject:FindFirstChild("Label")
		if not Label then return end

		Label.Text = Class.Label
		function Class:SetLabel(Text)
			Label.Text = Text
			return Class
		end
	end,

	[{
		Name="NoGradient",
		Aliases = {"NoGradientAll"},
		Recursive=true
	}] = function(GuiObject: GuiObject, Value, Class)
		local UIGradient = GuiObject:FindFirstChildOfClass("UIGradient")
		if not UIGradient then return end
		UIGradient.Enabled = not Value
	end,

	--// Addional functions for classes
	[{
		Name="Callback"
	}] = function(GuiObject: GuiObject, Value, Class)
		function Class:SetCallback(NewCallback)
			Class.Callback = NewCallback
			return Class
		end
		function Class:FireCallback(NewCallback)
			return Class.Callback(GuiObject)
		end
	end,

	[{
		Name="Value"
	}] = function(GuiObject: GuiObject, Value, Class)
		function Class:GetValue()
			return Class.Value
		end
	end,
}

function ImGui:GetName(Name: string)
	local Format = "%s_"
	return Format:format(Name)
end

function ImGui:CreateInstance(Class, Parent, Properties)
	local Object = Instance.new(Class)
	for Key, Value in next, Properties or {} do
		Object[Key] = Value
	end
	--// FIX: parent last (faster, and avoids the deprecated Instance.new parent argument)
	Object.Parent = Parent
	return Object
end

function ImGui:ApplyColors(ColorOverwrites, GuiObject: GuiObject, ElementType: string)
	for Info, Value in next, ColorOverwrites do
		local Key = Info
		local Recursive = false

		if typeof(Info) == "table" then
			Key = Info.Name or ""
			Recursive = Info.Recursive or false
		end

		--// Child object
		if typeof(Value) == "table" then
			local Element = GuiObject:FindFirstChild(Key, Recursive)

			if not Element then 
				if ElementType == "Window" then
					Element = GuiObject.Content:FindFirstChild(Key, Recursive)
					if not Element then continue end
				else 
					warn(Key, "was not found in", GuiObject)
					warn("Table:", Value)

					continue
				end
			end

			ImGui:ApplyColors(Value, Element)
			continue
		end

		--// Set property
		GuiObject[Key] = Value
	end
end

function ImGui:CheckStyles(GuiObject: GuiObject, Class, Colors)
	--// Addional styles
	for Info, Callback in next, AddionalStyles do
		local Value = Class[Info.Name]
		local Aliases = Info.Aliases

		if Aliases and not Value then
			for _, Alias in Info.Aliases do
				Value = Class[Alias]
				if Value then break end
			end
		end
		if Value == nil then continue end

		--// Stylise children
		Callback(GuiObject, Value, Class)
		if Info.Recursive then
			for _, Child in next, GuiObject:GetChildren() do
				Callback(Child, Value, Class)
			end
		end
	end

	--// Label functions/Styliser
	local ElementType = GuiObject.Name
	GuiObject.Name = self:GetName(ElementType)

	--// Apply Colors
	local Colors = Colors or {}
	local ColorOverwrites = Colors[ElementType]

	if ColorOverwrites then
		ImGui:ApplyColors(ColorOverwrites, GuiObject, ElementType)
	end

	--// Set properties
	for Key, Value in next, Class do
		pcall(function() --// If the property does not exist
			GuiObject[Key] = Value
		end)
	end
end

function ImGui:MergeMetatables(Class, Instance: GuiObject)
	local Metadata = {}
	Metadata.__index = function(self, Key)
		local Success, Value = pcall(function()
			local Value = Instance[Key]
			if typeof(Value) == "function" then
				return function(...)
					return Value(Instance, ...)
				end
			end
			return Value
		end)

		--// FIX: properties that are `false` (e.g. Visible) used to fall through to the class table
		if Success and Value ~= nil then
			return Value
		end
		return Class[Key]
	end

	Metadata.__newindex = function(self, Key, Value)
		local Key2 = Class[Key]
		if Key2 ~= nil or typeof(Value) == "function" then
			Class[Key] = Value
		else
			Instance[Key] = Value
		end
	end

	return setmetatable({}, Metadata)
end

function ImGui:Concat(Table, Separator: " ") 
	local Concatenated = ""
	for Index, String in next, Table do
		Concatenated ..= tostring(String) .. (Index ~= #Table and Separator or "")
	end
	return Concatenated
end

function ImGui:ContainerClass(Frame: Frame, Class, Window)
	local ContainerClass = Class or {}
	local WindowConfig = ImGui.Windows[Window]

	function ContainerClass:NewInstance(Instance: Frame, Class, Parent)
		--// Config
		Class = Class or {}

		--// Set Parent
		Instance.Parent = Parent or Frame
		Instance.Visible = true

		--// TODO
		if WindowConfig.NoGradientAll then
			Class.NoGradient = true
		end

		local Colors = WindowConfig.Colors
		ImGui:CheckStyles(Instance, Class, Colors)

		--// External callback check
		if Class.NewInstanceCallback then
			Class.NewInstanceCallback(Instance)
		end

		--// Merge the class with the properties of the instance
		return ImGui:MergeMetatables(Class, Instance)
	end

	function ContainerClass:Button(Config)
		Config = Config or {}
		local Button = Prefabs.Button:Clone()
		local ObjectClass = self:NewInstance(Button, Config)

		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end
		Button.Activated:Connect(Callback)

		--// Apply animations
		ImGui:ApplyAnimations(Button, "Buttons")
		return ObjectClass
	end

	function ContainerClass:Image(Config)
		Config = Config or {}
		local Image = Prefabs.Image:Clone()

		--// Check for rbxassetid
		if tonumber(Config.Image) then
			Config.Image = `rbxassetid://{Config.Image}`
		end

		local ObjectClass = self:NewInstance(Image, Config)
		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end
		Image.Activated:Connect(Callback)

		--// Apply animations
		ImGui:ApplyAnimations(Image, "Buttons")
		return ObjectClass
	end

	function ContainerClass:ScrollingBox(Config)
		Config = Config or {}
		local Box = Prefabs.ScrollBox:Clone()
		local ContainClass = ImGui:ContainerClass(Box, Config, Window) 
		return self:NewInstance(Box, ContainClass)
	end

	function ContainerClass:Label(Config)
		Config = Config or {}
		local Label = Prefabs.Label:Clone()
		return self:NewInstance(Label, Config)
	end

	function ContainerClass:Checkbox(Config)
		Config = Config or {}
		local IsRadio = Config.IsRadio

		local CheckBox = Prefabs.CheckBox:Clone()
		local Tickbox: ImageButton = CheckBox.Tickbox
		local Tick: ImageLabel = Tickbox.Tick
		local Label = CheckBox.Label
		local ObjectClass = self:NewInstance(CheckBox, Config)

		--// Stylise to correct type
		if IsRadio then
			Tick.ImageTransparency = 1
			Tick.BackgroundTransparency = 0
		else
			--// FIX: Remove() is deprecated, and the instances may be missing
			local TickPadding = Tickbox:FindFirstChildOfClass("UIPadding")
			local TickCorner = Tickbox:FindFirstChildOfClass("UICorner")
			if TickPadding then TickPadding:Destroy() end
			if TickCorner then TickCorner:Destroy() end
		end

		--// Apply animations
		ImGui:ApplyAnimations(CheckBox, "Buttons", Tickbox)

		local Value = Config.Value or false

		--// Callback
		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end

		function Config:SetTicked(NewValue: boolean, NoAnimation: false)
			Value = NewValue
			Config.Value = Value

			--// Animations
			local Size = Value and UDim2.fromScale(1,1) or UDim2.fromScale(0,0)
			ImGui:Tween(Tick, {
				Size = Size
			}, nil, NoAnimation)
			ImGui:Tween(Label, {
				TextTransparency = Value and 0 or 0.3
			}, nil, NoAnimation)

			--// Fire callback
			Callback(Value)

			return Config
		end
		Config:SetTicked(Value, true)

		function Config:Toggle()
			Config:SetTicked(not Value)
			return Config
		end

		--// Connect functions
		local function Clicked()
			Value = not Value
			Config:SetTicked(Value)
		end
		CheckBox.Activated:Connect(Clicked)
		Tickbox.Activated:Connect(Clicked)

		return ObjectClass
	end

	function ContainerClass:RadioButton(Config)
		Config = Config or {}
		Config.IsRadio = true
		return self:Checkbox(Config)
	end

	function ContainerClass:Viewport(Config)
		Config = Config or {}
		local Model = Config.Model

		local Holder = Prefabs.Viewport:Clone()
		local Viewport: ViewportFrame = Holder.Viewport
		local WorldModel: WorldModel = Viewport.WorldModel
		Config.WorldModel = WorldModel
		Config.Viewport = Viewport

		function Config:SetCamera(Camera)
			Viewport.CurrentCamera = Camera
			Config.Camera = Camera
			Camera.CFrame = CFrame.new(0,0,0)
			return Config
		end

		local Camera = Config.Camera or ImGui:CreateInstance("Camera", Viewport)
		Config:SetCamera(Camera)

		function Config:SetModel(Model: Model, PivotTo: CFrame)
			WorldModel:ClearAllChildren()

			--// Set new model
			if Config.Clone then
				Model = Model:Clone()
			end
			if PivotTo then
				Model:PivotTo(PivotTo)
			end

			Model.Parent = WorldModel
			Config.Model = Model
			return Model
		end

		--// Set model
		if Model then
			Config:SetModel(Model)
		end

		local ContainClass = ImGui:ContainerClass(Holder, Config, Window) 
		return self:NewInstance(Holder, ContainClass)
	end

	function ContainerClass:InputText(Config)
		Config = Config or {}
		local TextInput = Prefabs.TextInput:Clone()
		local TextBox: TextBox = TextInput.Input
		local ObjectClass = self:NewInstance(TextInput, Config)

		TextBox.Text = Config.Value or ""
		TextBox.PlaceholderText = Config.PlaceHolder or ""
		TextBox.MultiLine = Config.MultiLine == true

		--// Apply animations
		ImGui:ApplyAnimations(TextInput, "Inputs")

		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end
		TextBox:GetPropertyChangedSignal("Text"):Connect(function()
			local Value = TextBox.Text
			Config.Value = Value
			return Callback(Value)
		end)

		function Config:SetValue(Text)
			TextBox.Text = tostring(Text)
			Config.Value = Text
			return Config
		end

		function Config:Clear()
			TextBox.Text = ""
			return Config
		end

		return ObjectClass
	end

	function ContainerClass:InputTextMultiline(Config)
		Config = Config or {}
		Config.Label = ""
		Config.Size = UDim2.new(1, 0, 0, 38)
		Config.MultiLine = true
		return ContainerClass:InputText(Config)
	end

	function ContainerClass:GetRemainingHeight()
		local Padding = Frame:FindFirstChildOfClass("UIPadding")
		local UIListLayout = Frame:FindFirstChildOfClass("UIListLayout")

		local LayoutPaddding = UIListLayout.Padding
		local PaddingTop = Padding.PaddingTop
		local PaddingBottom = Padding.PaddingBottom

		local PaddingSizeY = PaddingTop+PaddingBottom+LayoutPaddding

		--// FIX: AbsoluteSize is in pixels, offsets are scaled by the window's UIScale
		local OccupiedY = ImGui:ToLocal(Frame.AbsoluteSize.Y)+PaddingSizeY.Offset+3

		return UDim2.new(1, 0, 1, -OccupiedY) 
	end

	function ContainerClass:Console(Config)
		Config = Config or {}
		local Console: ScrollingFrame = Prefabs.Console:Clone()
		local Source: TextBox = Console.Source
		local Lines = Console.Lines

		if Config.Fill then
			Console.Size = ContainerClass:GetRemainingHeight()
		end

		--// Set values from config
		Source.TextEditable = Config.ReadOnly ~= true
		Source.Text = Config.Text or ""
		Source.TextWrapped = Config.TextWrapped == true
		Source.RichText = Config.RichText == true
		Lines.Visible = Config.LineNumbers == true

		--// FIX: the console used to ignore SetText/AppendText unless `Enabled = true` was passed
		local function IsEnabled()
			return Config.Enabled ~= false
		end

		function Config:UpdateLineNumbers()
			if not Config.LineNumbers then return end

			local LinesCount = #Source.Text:split("\n")
			local Format = Config.LinesFormat or "%s"

			--// Update lines text
			Lines.Text = ""
			for i = 1, LinesCount do
				Lines.Text ..= `{Format:format(i)}{i ~= LinesCount and '\n' or ''}`
			end

			Source.Size = UDim2.new(1, -Lines.AbsoluteSize.X, 0, 0)
			return Config
		end

		function Config:UpdateScroll()
			local CanvasSizeY = Console.AbsoluteCanvasSize.Y
			Console.CanvasPosition = Vector2.new(0, CanvasSizeY)
			return Config
		end

		function Config:SetText(Text)
			if not IsEnabled() then return end
			Source.Text = Text
			Config:UpdateLineNumbers()
			return Config
		end

		function Config:GetValue()
			return Source.Text
		end

		function Config:Clear(Text)
			Source.Text = ""
			Config:UpdateLineNumbers()
			return Config
		end

		function Config:AppendText(...)
			if not IsEnabled() then return end

			local MaxLines = Config.MaxLines or 100
			local NewString = "\n" .. ImGui:Concat({...}, " ") 

			Source.Text ..= NewString
			Config:UpdateLineNumbers()

			if Config.AutoScroll then
				Config:UpdateScroll()
			end

			local Lines = Source.Text:split("\n")
			if #Lines > MaxLines then
				Source.Text = Source.Text:sub(#Lines[1]+2)
			end
			return Config
		end

		--// Connect events
		Source.Changed:Connect(function()
			Config:UpdateLineNumbers()
		end)

		return self:NewInstance(Console, Config)
	end

	function ContainerClass:Table(Config)
		Config = Config or {}
		local Table: Frame = Prefabs.Table:Clone()
		local TableChildCount = #Table:GetChildren() --// Performance

		--// Configure Table style
		if Config.Fill then
			Table.Size = ContainerClass:GetRemainingHeight()
		end
		local RowName = "Row"

		local RowsCount = 0
		function Config:CreateRow()
			local RowClass = {}

			local Row: Frame = Table.RowTemp:Clone()
			local UIListLayout = Row:FindFirstChildOfClass("UIListLayout")
			UIListLayout.VerticalAlignment = Enum.VerticalAlignment[Config.Align or "Center"]

			local RowChildCount = #Row:GetChildren() --// Performance
			Row.Name = RowName
			Row.Visible = true

			--// Background colors
			if Config.RowBackground then
				Row.BackgroundTransparency = RowsCount % 2 == 1 and 0.92 or 1
			end

			function RowClass:CreateColumn(CConfig)
				CConfig = CConfig or {}
				local Column: Frame = Row.ColumnTemp:Clone()
				Column.Visible = true
				Column.Name = "Column"

				local Stroke = Column:FindFirstChildOfClass("UIStroke")
				Stroke.Enabled = Config.Border ~= false

				local ContainClass = ImGui:ContainerClass(Column, CConfig, Window) 
				return ContainerClass:NewInstance(Column, ContainClass, Row)
			end

			function RowClass:UpdateColumns()
				if not Row or not Table then return end
				local Columns = Row:GetChildren()
				local RowsCount = #Columns - RowChildCount

				for _, Column: Frame in next, Columns do
					if not Column:IsA("Frame") then continue end
					Column.Size = UDim2.new(1/RowsCount, 0, 0, 0)
				end
				return RowClass
			end
			Row.ChildAdded:Connect(RowClass.UpdateColumns)
			Row.ChildRemoved:Connect(RowClass.UpdateColumns)

			RowsCount += 1
			return ContainerClass:NewInstance(Row, RowClass, Table)
		end

		function Config:UpdateRows()
			local Rows = Table:GetChildren()
			local PaddingY = Table.UIListLayout.Padding.Offset + 2
			local RowsCount = #Rows - TableChildCount

			for _, Row: Frame in next, Rows do
				if not Row:IsA("Frame") then continue end
				Row.Size = UDim2.new(1, 0, 1/RowsCount, -PaddingY)
			end
			return Config
		end

		if Config.RowsFill then
			Table.AutomaticSize = Enum.AutomaticSize.None
			Table.ChildAdded:Connect(Config.UpdateRows)
			Table.ChildRemoved:Connect(Config.UpdateRows)
		end

		function Config:ClearRows()
			RowsCount = 0
			local PostRowName = ImGui:GetName(RowName)
			for _, Row: Frame in next, Table:GetChildren() do
				if not Row:IsA("Frame") then continue end

				if Row.Name == PostRowName then
					Row:Destroy()
				end
			end
			return Config
		end

		return self:NewInstance(Table, Config) 
	end

	function ContainerClass:Grid(Config)
		Config = Config or {}
		Config.Grid = true

		return self:Table(Config)
	end

	function ContainerClass:CollapsingHeader(Config)
		Config = Config or {}
		local Title = Config.Title or ""
		Config.Name = Title

		local Header = Prefabs.CollapsingHeader:Clone()
		local Titlebar: TextButton = Header.TitleBar
		local Container: Frame = Header.ChildContainer
		Titlebar.Title.Text = Title

		--// Apply animations
		if Config.IsTree then
			ImGui:ApplyAnimations(Titlebar, "Tabs")
		else
			ImGui:ApplyAnimations(Titlebar, "Buttons")
		end

		--// Open Animations
		function Config:SetOpen(Open)
			local Animate = Config.NoAnimation ~= true
			Config.Open = Open
			ImGui:HeaderAnimate(Header, Animate, Open, Titlebar)
			return self
		end

		--// Toggle
		local ToggleButton = Titlebar.Toggle.ToggleButton
		local function Toggle()
			Config:SetOpen(not Config.Open)
		end
		Titlebar.Activated:Connect(Toggle)
		ToggleButton.Activated:Connect(Toggle)

		--// Custom toggle image
		if Config.Image then
			ToggleButton.Image = Config.Image 
		end

		--// Open
		Config:SetOpen(Config.Open or false)

		local ContainClass = ImGui:ContainerClass(Container, Config, Window) 
		return self:NewInstance(Header, ContainClass)
	end

	function ContainerClass:TreeNode(Config)
		Config = Config or {}
		Config.IsTree = true
		return self:CollapsingHeader(Config)
	end

	function ContainerClass:Separator(Config)
		Config = Config or {}
		local Separator = Prefabs.SeparatorText:Clone()
		local HeaderLabel = Separator.TextLabel
		HeaderLabel.Text = Config.Text or ""

		if not Config.Text then
			HeaderLabel.Visible = false
		end

		return self:NewInstance(Separator, Config)
	end

	function ContainerClass:Row(Config)
		Config = Config or {}
		local Row: Frame = Prefabs.Row:Clone()
		local UIListLayout = Row:FindFirstChildOfClass("UIListLayout")
		local UIPadding = Row:FindFirstChildOfClass("UIPadding")

		if Config.Spacing then
			UIListLayout.Padding = UDim.new(0, Config.Spacing)
		end

		function Config:Fill()
			local Children = Row:GetChildren()
			local Rows = #Children - 2 --// -UIListLayout + UIPadding

			--// Change layout
			local Padding = UIListLayout.Padding.Offset * 2
			UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

			--// Apply correct margins
			UIPadding.PaddingLeft = UIListLayout.Padding
			UIPadding.PaddingRight = UIListLayout.Padding

			for _, Child: Instance in next, Children do
				local YScale = 0
				if Child:IsA("ImageButton") then
					YScale = 1
				end
				pcall(function()
					Child.Size = UDim2.new(1/Rows, -Padding, YScale, 0)
				end)
			end
			return Config
		end

		local ContainClass = ImGui:ContainerClass(Row, Config, Window) 
		return self:NewInstance(Row, ContainClass)
	end

	--TODO
	-- Vertical 
	-- :SetPercentage
	-- This will use UIDragdetectors in the upcoming release, please do not report this!
	function ContainerClass:Slider(Config)
		Config = Config or {}

		--// FIX: MinValue/MaxValue used to error when they weren't provided
		Config.MinValue = Config.MinValue or 0
		Config.MaxValue = Config.MaxValue or 100

		--// Unpack config
		local Value = Config.Value or Config.MinValue
		local ValueFormat = Config.Format or "%.d"
		local IsProgress = Config.Progress
		Config.Name = Config.Label or ""

		--// Slider element
		local Slider: TextButton = Prefabs.Slider:Clone()
		local UIPadding = Slider:FindFirstChildOfClass("UIPadding")
		local Grab: Frame = Slider.Grab
		local ValueText = Slider.ValueText
		local Label = Slider.Label

		local ObjectClass = self:NewInstance(Slider, Config)

		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end

		--// Apply Progress styles
		if IsProgress then
			local UIGradient = Grab:FindFirstChildOfClass("UIGradient")

			local PaddingSides = UDim.new(0,2)
			local Diff = UIPadding.PaddingLeft - PaddingSides

			Grab.AnchorPoint = Vector2.new(0, 0.5)
			if UIGradient then
				UIGradient.Enabled = true
			end

			UIPadding.PaddingLeft = PaddingSides
			UIPadding.PaddingRight = PaddingSides

			Label.Position = UDim2.new(1, 15-Diff.Offset, 0, 0)
		end

		function Config:SetValue(Value: number, Slider: false)
			local MinValue = Config.MinValue
			local MaxValue = Config.MaxValue
			local Difference = MaxValue - MinValue
			local Percentage = 0

			if not Slider then
				Value = tonumber(Value) or MinValue
				Value = math.clamp(Value, math.min(MinValue, MaxValue), math.max(MinValue, MaxValue))
				Percentage = Difference ~= 0 and (Value - MinValue) / Difference or 0
			else
				Percentage = Value
				Value = MinValue + (Difference * Percentage)
			end

			Percentage = math.clamp(Percentage, 0, 1)

			--// Animate grab
			local Props = {
				Position = UDim2.fromScale(Percentage, 0.5)
			}

			if IsProgress then
				Props = {
					Size = UDim2.fromScale(Percentage, 1)
				}
			end

			--// Animate
			ImGui:Tween(Grab, Props)

			--// Update UI
			Config.Value = Value
			ValueText.Text = ValueFormat:format(Value, MaxValue) 

			--// Fire callback
			Callback(Value)

			return Config
		end

		--// Position -> percentage (takes the slider's padding into account)
		local function SetFromX(X: number)
			local Width = Slider.AbsoluteSize.X
			local PadLeft, PadRight = 0, 0

			if UIPadding then
				local Scale = ImGui:GetScale()
				PadLeft = UIPadding.PaddingLeft.Scale * Width + UIPadding.PaddingLeft.Offset * Scale
				PadRight = UIPadding.PaddingRight.Scale * Width + UIPadding.PaddingRight.Offset * Scale
			end

			local Left = Slider.AbsolutePosition.X + PadLeft
			local Span = math.max(Width - PadLeft - PadRight, 1)

			Config:SetValue(math.clamp((X - Left) / Span, 0, 1), true)
		end

		--// FIX: mouse + touch dragging (used Mouse.Move / GetMouseLocation which don't work on mobile)
		local ScrollParent: ScrollingFrame? = nil
		local ScrollWasEnabled = true

		ImGui:ConnectDrag({
			Target = Slider,
			CanStart = function()
				return not Config.ReadOnly
			end,
			Started = function(Input)
				--// Stop the page from scrolling while dragging the slider with a finger
				local Parent = Slider.Parent
				while Parent do
					if Parent:IsA("ScrollingFrame") then
						ScrollParent = Parent
						ScrollWasEnabled = Parent.ScrollingEnabled
						Parent.ScrollingEnabled = false
						break
					end
					Parent = Parent.Parent
				end

				SetFromX(Input.Position.X)
			end,
			Moved = function(Input)
				SetFromX(Input.Position.X)
			end,
			Ended = function()
				if ScrollParent then
					ScrollParent.ScrollingEnabled = ScrollWasEnabled
					ScrollParent = nil
				end
			end
		})

		--// Update UI
		Config:SetValue(Value)

		return ObjectClass
	end

	function ContainerClass:ProgressSlider(Config)
		Config = Config or {}
		Config.Progress = true
		return self:Slider(Config)
	end

	function ContainerClass:ProgressBar(Config)
		Config = Config or {}
		Config.Progress = true
		Config.ReadOnly = true
		Config.MinValue = 0
		Config.MaxValue = 100
		Config.Format = "% i%%"
		Config = self:Slider(Config)

		function Config:SetPercentage(Value: number)
			Config:SetValue(Value)
		end

		return Config
	end

	function ContainerClass:Keybind(Config)
		Config = Config or {}

		local Key = Config.Value
		local TobeNullKey = Config.NullKey or Enum.KeyCode.Backspace

		local Keybind: TextButton = Prefabs.Keybind:Clone()
		local ValueText: TextButton = Keybind.ValueText
		local Listening = false

		local ObjectClass = nil
		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end

		local function UpdateText()
			ValueText.Text = Config.Value and Config.Value.Name or "Not set"
		end

		function Config:SetValue(NewKey: Enum.KeyCode)
			if not NewKey then
				UpdateText()
				return Config
			end

			if NewKey == TobeNullKey then
				Config.Value = nil
			else
				Config.Value = NewKey
			end

			UpdateText()
			return Config
		end

		Keybind.Activated:Connect(function()
			--// FIX: devices without a keyboard can't bind keys, so tapping fires the keybind instead
			if not UserInputService.KeyboardEnabled then
				return Callback(Config.Value)
			end

			if Listening then return end
			Listening = true
			ValueText.Text = "..."

			local NewInput = UserInputService.InputBegan:Wait()
			Listening = false

			--// FIX: used to get stuck on "..." when cancelled/unfocused
			if not UserInputService.WindowFocused or NewInput.UserInputType ~= Enum.UserInputType.Keyboard then
				return UpdateText()
			end

			task.wait(.1) --// 👍
			Config:SetValue(NewInput.KeyCode)
		end)

		Config.Connection = UserInputService.InputBegan:Connect(function(Input, GameProcessed)
			if Listening then return end
			if not Config.IgnoreGameProcessed and GameProcessed then return end
			local KeyCode = Input.KeyCode
			local Match = Config.Value

			if KeyCode == TobeNullKey then return end
			if KeyCode ~= Match then return end 

			return Callback(Input.KeyCode)
		end)

		--// Disconnect when the element is removed
		Keybind.Destroying:Connect(function()
			if Config.Connection then
				Config.Connection:Disconnect()
			end
		end)

		--// Update UI
		Config.Value = nil
		Config:SetValue(Key)

		ObjectClass = self:NewInstance(Keybind, Config)
		return ObjectClass
	end

	function ContainerClass:Combo(Config)
		Config = Config or {}
		Config.Open = false
		Config.Value = ""

		local Combo: TextButton = Prefabs.Combo:Clone()
		local Toggle: ImageButton = Combo.Toggle.ToggleButton
		local ValueText = Combo.ValueText
		ValueText.Text = Config.Placeholder or ""

		local Dropdown = nil
		local ObjectClass = self:NewInstance(Combo, Config)

		local ComboHovering = ImGui:ConnectHover({
			Parent = Combo
		})

		local function Callback(Value, ...)
			local func = Config.Callback or NullFunction
			Config:SetOpen(false)
			return func(ObjectClass, Value, ...)
		end

		function Config:SetValue(Value, ...)
			local Items = Config.Items or {}
			local DictValue = Items[Value]
			ValueText.Text = tostring(Value)
			Config.Value = Value

			return Callback(DictValue or Value) 
		end

		function Config:SetOpen(Open: true)
			local Animate = Config.NoAnimation ~= true
			ImGui:HeaderAnimate(Combo, Animate, Open, Combo, Toggle)
			Config.Open = Open

			if Open then
				Dropdown = ImGui:Dropdown({
					Parent = Combo,
					Items = Config.Items or {},
					SetValue = Config.SetValue,
					Closed = function()
						if not ComboHovering.Hovering then 
							Config:SetOpen(false)
						end
					end,
				})
			end

			return self
		end

		local function ToggleOpen()
			--// FIX: remember the state first, closing the dropdown can flip it (caused re-opening on touch)
			local WasOpen = Config.Open

			if Dropdown then
				Dropdown:Close()
			end
			Config:SetOpen(not WasOpen)
		end

		--// Connect events
		Combo.Activated:Connect(ToggleOpen)
		Toggle.Activated:Connect(ToggleOpen)
		ImGui:ApplyAnimations(Combo, "Buttons")

		if Config.Selected then
			Config:SetValue(Config.Selected)
		end

		return ObjectClass 
	end

	return ContainerClass
end

function ImGui:Dropdown(Config)
	local Parent: GuiObject = Config.Parent
	if not Parent then return end

	local Selection: ScrollingFrame = Prefabs.Selection:Clone()
	local UIStroke = Selection:FindFirstChildOfClass("UIStroke")

	local Scale = self:GetScale()
	local Padding = UIStroke and UIStroke.Thickness*2 or 2
	local Position = Parent.AbsolutePosition
	local Size = Parent.AbsoluteSize

	Selection.Parent = self.ScreenGui
	Selection.Position = UDim2.fromOffset(Position.X+Padding, Position.Y+Size.Y)

	--// Match the window scale (touch devices)
	self:CreateInstance("UIScale", Selection, {Scale = Scale})

	local Closed = false

	--// Mouse: close when clicking outside. Touch: close when tapping outside of the list and the combo
	local Hover = self:ConnectHover({
		Parent = Selection,
		OnInput = function(MouseHovering, Input)
			if Input.UserInputType == Touch then
				if IsPointInside(Selection, Input.Position) then return end
				if IsPointInside(Parent, Input.Position) then return end
				return Config:Close()
			end

			if not Input.UserInputType.Name:find("Mouse") then return end

			if not MouseHovering then
				Config:Close()
			end
		end,
	})

	function Config:Close()
		--// FIX: closing twice used to fire the callback twice
		if Closed then return end
		Closed = true

		local CloseCallback = Config.Closed
		if CloseCallback then
			CloseCallback()
		end

		Hover:Disconnect()
		Selection:Destroy()
	end

	local function SetValue(Value)
		Config:Close()
		Config:SetValue(Value)
	end

	--// Append items
	local ItemTemplate: TextButton = Selection.Template
	ItemTemplate.Visible = false

	for Index, Index2 in next, Config.Items do
		local Value = typeof(Index) ~= "number" and Index or Index2

		local NewItem: TextButton = ItemTemplate:Clone()
		NewItem.Text = tostring(Value)
		NewItem.Parent = Selection
		NewItem.Visible = true
		NewItem.Activated:Connect(function()
			return SetValue(Value)
		end)

		self:ApplyAnimations(NewItem, "Tabs")
	end

	--// Configure size of the frame
	-- Roblox does not support UISizeConstraint on a scrolling frame grr

	local MaxSizeY = Config.MaxSizeY or 200
	local YSize = math.clamp(Selection.AbsoluteCanvasSize.Y / Scale, Size.Y / Scale, MaxSizeY)
	Selection.Size = UDim2.fromOffset((Size.X-Padding) / Scale, YSize)

	--// Open upwards if there is no room below (small phone screens)
	local Viewport = self:GetViewportSize()
	local HeightPx = YSize * Scale
	if Position.Y + Size.Y + HeightPx > Viewport.Y and Position.Y - HeightPx >= 0 then
		Selection.Position = UDim2.fromOffset(Position.X+Padding, Position.Y-HeightPx)
	end

	return Config
end

function ImGui:GetAnimation(Animation: boolean?)
	return Animation and self.Animation or TweenInfo.new(0)
end

function ImGui:Tween(Instance: GuiObject, Props: SharedTable, tweenInfo, NoAnimation: false)
	local tweenInfo = tweenInfo or ImGui:GetAnimation(not NoAnimation)
	local Tween = TweenService:Create(Instance, 
		tweenInfo,
		Props
	)
	Tween:Play()
	return Tween
end

function ImGui:ApplyAnimations(Instance: GuiObject, Class: string, Target: GuiObject?)
	local Animatons = ImGui.Animations
	local ColorProps = Animatons[Class]

	if not ColorProps then 
		return warn("No colors for", Class)
	end

	--// Apply tweens for connections
	local Connections = {}
	for Connection, Props in next, ColorProps do
		if typeof(Props) ~= "table" then continue end
		local Target = Target or Instance
		local Callback = function()
			ImGui:Tween(Target, Props)
		end

		--// Connections
		Connections[Connection] = Callback
		Instance[Connection]:Connect(Callback)
	end

	--// Reset colors
	if Connections["MouseLeave"] then
		Connections["MouseLeave"]()

		--// FIX: MouseLeave is unreliable for touches, reset the hover state when the finger lifts
		if UserInputService.TouchEnabled then
			local MouseLeave = Connections["MouseLeave"]
			Instance.InputEnded:Connect(function(Input)
				if Input.UserInputType == Touch then
					MouseLeave()
				end
			end)
		end
	end

	return Connections 
end

function ImGui:HeaderAnimate(Header: Instance, Animation, Open, TitleBar: Instance, Toggle)
	local ToggleButtion = Toggle or TitleBar.Toggle.ToggleButton

	--// Togle animation
	ImGui:Tween(ToggleButtion, {
		Rotation = Open and 90 or 0,
	})

	--// Container animation
	local Container: Frame = Header:FindFirstChild("ChildContainer")
	if not Container then return end

	local UIListLayout: UIListLayout = Container.UIListLayout
	local UIPadding: UIPadding = Container:FindFirstChildOfClass("UIPadding")

	--// FIX: AbsoluteContentSize is in pixels, sizes are scaled by the window's UIScale
	local ContentSize = UIListLayout.AbsoluteContentSize / ImGui:GetScale()

	if UIPadding then
		local Top = UIPadding.PaddingTop.Offset
		local Bottom = UIPadding.PaddingBottom.Offset
		ContentSize = Vector2.new(ContentSize.X, ContentSize.Y+Top+Bottom)
	end

	Container.AutomaticSize = Enum.AutomaticSize.None
	if not Open then
		Container.Size = UDim2.new(1, -10, 0, ContentSize.Y)
	end

	--// Animate
	local Tween = ImGui:Tween(Container, {
		Size = UDim2.new(1, -10, 0, Open and ContentSize.Y or 0),
		Visible = Open
	})
	Tween.Completed:Connect(function()
		if not Open then return end
		Container.AutomaticSize = Enum.AutomaticSize.Y
		Container.Size = UDim2.new(1, -10, 0, 0)
	end)
end

--// Shared mouse + touch drag handling
--// Config: Target (GuiObject that starts the drag), CanStart, Started(Input), Moved(Input, Delta), Ended(Input)
function ImGui:ConnectDrag(Config)
	local Target: GuiObject = Config.Target
	local Active: InputObject? = nil
	local StartPosition: Vector3? = nil

	local Connections = {}

	local function IsActiveMove(Input: InputObject)
		if not Active then return false end

		--// Touch InputObjects are reused for the life of the touch
		if Active.UserInputType == Touch then
			return Input == Active or Input.UserInputType == Touch
		end
		return Input.UserInputType == MouseMovement
	end

	table.insert(Connections, Target.InputBegan:Connect(function(Input)
		if Active or not IsPointerStart(Input) then return end
		if Config.CanStart and not Config.CanStart(Input) then return end

		Active = Input
		StartPosition = Input.Position

		if Config.Started then
			Config.Started(Input)
		end
	end))

	table.insert(Connections, UserInputService.InputChanged:Connect(function(Input)
		if not IsActiveMove(Input) then return end
		if Config.Moved then
			Config.Moved(Input, Input.Position - StartPosition)
		end
	end))

	table.insert(Connections, UserInputService.InputEnded:Connect(function(Input)
		if not Active then return end
		if Input ~= Active and Input.UserInputType ~= Active.UserInputType then return end

		Active = nil
		if Config.Ended then
			Config.Ended(Input)
		end
	end))

	function Config:Disconnect()
		for _, Connection in next, Connections do
			Connection:Disconnect()
		end
	end

	--// FIX: global connections used to leak after a widget/window was destroyed
	table.insert(Connections, Target.Destroying:Connect(function()
		Config:Disconnect()
	end))

	return Config
end

function ImGui:ApplyDraggable(Frame: Frame, Header: Frame)
	local Header = Header or Frame
	local BeganPos = Frame.Position

	return self:ConnectDrag({
		Target = Header,
		Started = function()
			BeganPos = Frame.Position
		end,
		Moved = function(Input, Delta)
			--// Set directly instead of tweening, much smoother on touch screens
			Frame.Position = UDim2.new(
				BeganPos.X.Scale, 
				BeganPos.X.Offset + Delta.X, 
				BeganPos.Y.Scale, 
				BeganPos.Y.Offset + Delta.Y
			)
		end,
		Ended = function()
			ImGui:ClampWindowPosition(Frame)
		end
	})
end

function ImGui:ApplyResizable(MinSize, Frame: Frame, Dragger: TextButton, Config)
	local OrignialSize = Frame.AbsoluteSize

	MinSize = MinSize or Vector2.new(160, 90)

	return self:ConnectDrag({
		Target = Dragger,
		Started = function()
			OrignialSize = Frame.AbsoluteSize
		end,
		Moved = function(Input, Delta)
			local Scale = ImGui:GetScale()
			local Viewport = ImGui:GetViewportSize()

			--// Pixels -> local units (the window may be scaled)
			local NewX = (OrignialSize.X + Delta.X) / Scale
			local NewY = (OrignialSize.Y + Delta.Y) / Scale

			if ImGui.ClampToScreen then
				NewX = math.min(NewX, Viewport.X / Scale)
				NewY = math.min(NewY, Viewport.Y / Scale)
			end

			local NewSize = UDim2.fromOffset(
				math.max(MinSize.X, NewX), 
				math.max(MinSize.Y, NewY)
			)

			Frame.Size = NewSize
			if Config then
				Config.Size = NewSize
			end
		end,
		Ended = function()
			ImGui:ClampWindowPosition(Frame)
		end
	})
end

function ImGui:ConnectHover(Config)
	local Parent = Config.Parent
	local Connections = {}
	Config.Hovering = false

	--// Connect Events
	table.insert(Connections, Parent.MouseEnter:Connect(function()
		Config.Hovering = true
	end))
	table.insert(Connections, Parent.MouseLeave:Connect(function()
		Config.Hovering = false
	end))

	if Config.OnInput then
		table.insert(Connections, UserInputService.InputBegan:Connect(function(Input)
			return Config.OnInput(Config.Hovering, Input)
		end))
	end

	function Config:Disconnect()
		for _, Connection in next, Connections do
			Connection:Disconnect()
		end
	end

	--// Clean up with the instance
	table.insert(Connections, Parent.Destroying:Connect(function()
		Config:Disconnect()
	end))

	return Config
end

function ImGui:ApplyWindowSelectEffect(Window: GuiObject, TitleBar)
	local UIStroke = Window:FindFirstChildOfClass("UIStroke")

	local Colors = {
		Selected = {
			BackgroundColor3 = TitleBar.BackgroundColor3
		},
		Deselected = {
			BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		}
	}

	local function SetSelected(Selected)
		local Animations = ImGui.Animations
		local Type = Selected and "Selected" or "Deselected"

		ImGui:Tween(TitleBar, Colors[Type])
		if UIStroke then
			ImGui:Tween(UIStroke, Animations.WindowBorder[Type])
		end
	end

	self:ConnectHover({
		Parent = Window,
		OnInput = function(MouseHovering, Input)
			--// FIX: touch screens have no hover, select the window by tapping inside it
			if Input.UserInputType == Touch then
				SetSelected(IsPointInside(Window, Input.Position))
			elseif Input.UserInputType.Name:find("Mouse") then
				SetSelected(MouseHovering)
			end
		end,
	})
end

function ImGui:SetWindowProps(Properties, IgnoreWindows)
	IgnoreWindows = IgnoreWindows or {}

	local Module = {
		OldProperties = {}
	}

	--// Collect windows & set properties
	for Window in next, ImGui.Windows do
		if table.find(IgnoreWindows, Window) then continue end

		local OldValues = {}
		Module.OldProperties[Window] = OldValues

		for Key, Value in next, Properties do
			OldValues[Key] = Window[Key]
			Window[Key] = Value
		end
	end

	--// Revert to previous values
	function Module:Revert()
		for Window in next, ImGui.Windows do
			local OldValues = Module.OldProperties[Window]
			if not OldValues then continue end

			for Key, Value in next, OldValues do
				Window[Key] = Value
			end
		end
	end

	return Module
end

function ImGui:ToLocal(Pixels: number): number
	return Pixels / self:GetScale()
end

function ImGui:CreateWindow(WindowConfig)
	WindowConfig = WindowConfig or {}

	--// Create Window frame
	local Window: Frame = Prefabs.Window:Clone()
	Window.Parent = ImGui.ScreenGui
	Window.Visible = true
	WindowConfig.Window = Window

	--// Scale (bigger UI on touch screens)
	ImGui:CreateInstance("UIScale", Window, {
		Scale = ImGui:GetScale()
	})

	local Content = Window.Content
	local Body = Content.Body

	--// Window Resize
	local Resize = Window.ResizeGrab
	Resize.Visible = WindowConfig.NoResize ~= true

	local MinSize = WindowConfig.MinSize or Vector2.new(160, 90)
	ImGui:ApplyResizable(
		MinSize, 
		Window, 
		Resize,
		WindowConfig
	)

	--// Title Bar
	local TitleBar: Frame = Content.TitleBar
	TitleBar.Visible = WindowConfig.NoTitleBar ~= true

	local Toggle = TitleBar.Left.Toggle
	Toggle.Visible = WindowConfig.NoCollapse ~= true
	ImGui:ApplyAnimations(Toggle.ToggleButton, "Tabs")

	local ToolBar = Content.ToolBar
	ToolBar.Visible = WindowConfig.TabsBar ~= false

	--// FIX: windows used to drag from anywhere, which made touch scrolling and sliders drag the window
	if not WindowConfig.NoDrag then
		local DragHandle = TitleBar
		if WindowConfig.NoTitleBar or WindowConfig.DragAnywhere then
			DragHandle = Window
		end
		ImGui:ApplyDraggable(Window, DragHandle)
	end

	--// Close Window 
	local CloseButton: TextButton = TitleBar.Close
	CloseButton.Visible = WindowConfig.NoClose ~= true

	function WindowConfig:Close()
		local Callback = WindowConfig.CloseCallback
		WindowConfig:SetVisible(false)
		if Callback then
			Callback(WindowConfig)
		end
		return WindowConfig
	end
	CloseButton.Activated:Connect(WindowConfig.Close)

	function WindowConfig:GetHeaderSizeY(): number
		--// Pixels -> local units
		local ToolbarY = ToolBar.Visible and ToolBar.AbsoluteSize.Y or 0
		local TitlebarY = TitleBar.Visible and TitleBar.AbsoluteSize.Y or 0
		return ImGui:ToLocal(ToolbarY + TitlebarY)
	end

	function WindowConfig:UpdateBody()
		local HeaderSizeY = self:GetHeaderSizeY()
		Body.Size = UDim2.new(1, 0, 1, -HeaderSizeY)
	end
	WindowConfig:UpdateBody()

	--// Open/Close
	WindowConfig.Open = true
	function WindowConfig:SetOpen(Open: true, NoAnimation: false)
		local WindowAbSize = Window.AbsoluteSize 
		local TitleBarSize = TitleBar.AbsoluteSize 

		self.Open = Open

		--// Call animations
		ImGui:HeaderAnimate(TitleBar, true, Open, TitleBar, Toggle.ToggleButton)
		ImGui:Tween(Resize, {
			TextTransparency = Open and 0.6 or 1,
			Interactable = Open
		}, nil, NoAnimation)
		ImGui:Tween(Window, {
			Size = Open and (self.Size or Window.Size) or UDim2.fromOffset(
				ImGui:ToLocal(WindowAbSize.X), 
				ImGui:ToLocal(TitleBarSize.Y)
			)
		}, nil, NoAnimation)
		ImGui:Tween(Body, {
			Visible = Open
		}, nil, NoAnimation)
		return self
	end

	function WindowConfig:SetVisible(Visible: boolean)
		Window.Visible = Visible 
		return self
	end

	function WindowConfig:SetTitle(Text)
		TitleBar.Left.Title.Text = tostring(Text)
		return self
	end
	function WindowConfig:Remove()
		Window:Destroy()
		return self
	end

	Toggle.ToggleButton.Activated:Connect(function()
		local Open = not WindowConfig.Open
		WindowConfig.Open = Open
		return WindowConfig:SetOpen(Open)
	end)	

	function WindowConfig:CreateTab(Config)
		local Name = Config.Name or ""
		local TabButton = ToolBar.TabButton:Clone()
		TabButton.Name = Name
		TabButton.Text = Name
		TabButton.Visible = true
		TabButton.Parent = ToolBar
		Config.Button = TabButton

		local AutoSizeAxis = WindowConfig.AutoSize or "Y"
		local Content: Frame = Body.Template:Clone()
		Content.AutomaticSize = Enum.AutomaticSize[AutoSizeAxis]
		Content.Visible = Config.Visible or false
		Content.Name = Name
		Content.Parent = Body
		Config.Content = Content

		if AutoSizeAxis == "Y" then
			Content.Size = UDim2.fromScale(1, 0)
		elseif AutoSizeAxis == "X" then
			Content.Size = UDim2.fromScale(0, 1)
		end

		TabButton.Activated:Connect(function()
			WindowConfig:ShowTab(Config)
		end)

		function Config:GetContentSize()
			return Content.AbsoluteSize
		end

		--// Apply animations
		Config = ImGui:ContainerClass(Content, Config, Window)
		ImGui:ApplyAnimations(TabButton, "Tabs")

		--// Automatic sizes
		self:UpdateBody()
		if WindowConfig.AutoSize then
			Content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				local Size = Config:GetContentSize()
				self:SetSize(Size)
			end)
		end

		return Config
	end

	function WindowConfig:SetPosition(Position)
		Window.Position = Position
		return self
	end

	function WindowConfig:SetSize(Size)
		local HeaderSizeY = self:GetHeaderSizeY()

		if typeof(Size) == "Vector2" then
			--// Pixels -> local units (Vector2 sizes come from AbsoluteSize)
			Size = UDim2.fromOffset(ImGui:ToLocal(Size.X), ImGui:ToLocal(Size.Y))
		end

		--// Apply new size
		local NewSize = UDim2.new(
			Size.X.Scale,
			Size.X.Offset,
			Size.Y.Scale,
			Size.Y.Offset + HeaderSizeY
		)
		NewSize = ImGui:ClampSizeToScreen(NewSize)

		self.Size = NewSize
		Window.Size = NewSize

		return self
	end

	--// Tab change system 
	function WindowConfig:ShowTab(TabClass: SharedTable)
		local TargetPage: Frame = TabClass.Content

		--// Page animation
		if not TargetPage.Visible and not TabClass.NoAnimation then
			TargetPage.Position = UDim2.fromOffset(0, 5)
		end

		--// Hide other tabs
		for _, Page in next, Body:GetChildren() do
			Page.Visible = Page == TargetPage
		end

		--// Page animation
		ImGui:Tween(TargetPage, {
			Position = UDim2.fromOffset(0, 0)
		})
		return self
	end

	function WindowConfig:Center() --// Without an Anchor point
		local Size = Window.AbsoluteSize
		local Position = UDim2.new(0.5,-Size.X/2,0.5,-Size.Y/2)
		self:SetPosition(Position)
		return self
	end

	--// Load Style Configs
	WindowConfig:SetTitle(WindowConfig.Title or "Depso UI")

	if not WindowConfig.Open then
		WindowConfig:SetOpen(WindowConfig.Open or true, true)
	end

	--// Keep the window on screen
	if typeof(WindowConfig.Size) == "UDim2" then
		WindowConfig.Size = ImGui:ClampSizeToScreen(WindowConfig.Size)
	end

	ImGui.Windows[Window] = WindowConfig
	Window.Destroying:Connect(function()
		ImGui.Windows[Window] = nil
	end)

	ImGui:CheckStyles(Window, WindowConfig, WindowConfig.Colors)

	--// FIX: collapsing a window used to error when no Size was given
	if typeof(WindowConfig.Size) ~= "UDim2" then
		WindowConfig.Size = Window.Size
	end

	task.defer(function()
		ImGui:ClampWindowPosition(Window)
	end)

	--// Window section events
	if not WindowConfig.NoSelectEffect then
		ImGui:ApplyWindowSelectEffect(Window, TitleBar)
	end

	return ImGui:MergeMetatables(WindowConfig, Window)
end

function ImGui:CreateModal(Config)
	local ModalEffect = Prefabs.ModalEffect:Clone()
	ModalEffect.BackgroundTransparency = 1
	ModalEffect.Parent = ImGui.FullScreenGui
	ModalEffect.Visible = true

	ImGui:Tween(ModalEffect, {
		BackgroundTransparency = 0.6
	})

	--// Config
	Config = Config or {}
	Config.TabsBar = Config.TabsBar ~= nil and Config.TabsBar or false
	Config.NoCollapse = true
	Config.NoResize = true
	Config.NoClose = true
	Config.NoSelectEffect = true
	Config.Parent = ModalEffect

	--// Center
	Config.AnchorPoint = Vector2.new(0.5, 0.5)
	Config.Position = UDim2.fromScale(0.5, 0.5)

	--// Create Window
	local Window = self:CreateWindow(Config)
	Config = Window:CreateTab({
		Visible = true
	})

	--// Disable other windows
	local WindowManger = ImGui:SetWindowProps({
		Interactable = false
	}, {Window.Window})

	--// Close functions
	local WindowClose = Window.Close
	function Config:Close()
		local Tween = ImGui:Tween(ModalEffect, {
			BackgroundTransparency = 1
		})
		Tween.Completed:Connect(function()
			ModalEffect:Destroy()
		end)

		WindowManger:Revert()
		WindowClose()
	end

	return Config
end

--// ScreenGuis
--// FIX: CoreGui isn't always accessible (some mobile executors), try gethui() -> CoreGui -> PlayerGui
local function CreateGui(Properties)
	local Gui = ImGui:CreateInstance("ScreenGui", nil, Properties)

	if not IsStudio then
		local Parents = {
			function() return gethui and gethui() end,
			function() return CoreGui end
		}

		for _, GetParent in Parents do
			local Success, Parent = pcall(GetParent)
			if Success and typeof(Parent) == "Instance" then
				if pcall(function() Gui.Parent = Parent end) and Gui.Parent == Parent then
					return Gui
				end
			end
		end
	end

	Gui.Parent = PlayerGui
	return Gui
end

ImGui.ScreenGui = CreateGui({
	Name = "DepsoImGui",
	DisplayOrder = 9999,
	ResetOnSpawn = false
})
ImGui.FullScreenGui = CreateGui({
	Name = "DepsoImGuiFullscreen",
	DisplayOrder = 99999,
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.None
})

return ImGui
