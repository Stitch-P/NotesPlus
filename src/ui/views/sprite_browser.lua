local Base = require("src/ui/views/view")
local Browser = require("src/ui/pickers/sprite_browser")
local Gear = require("src/notes/gear")

local View = {}
View.__index = View
setmetatable(View, {__index = Base})

function View.new(parent, options, callbacks)
    local self = Base.Init(setmetatable({}, View), parent, options, callbacks)
    self.draft, self.slot = options.draft, options.slot
    local gear = self.view == "gearItems"
    local category = self.view == "categorySprites"
    self:Heading(gear and ("Choose " .. self.slot.label:lower() .. " item") or "Choose sprite")
    local selected = gear and (self.draft.gear[self.slot.key] or "") or self.draft.skill
    local function back()
        self:Navigate(category and "category" or "edit", {draft = self.draft})
    end
    self.spriteBrowser = Browser.new(self.surface, self.width, self.height, selected, function(name)
        if gear then
            if name ~= "" and not Gear.GetItem(name) then return end
            self.draft.gear[self.slot.key] = name ~= "" and name or nil
        else self.draft.skill = name end
        back()
    end, back, prettyui.Tooltip.getContext(self.window.chrome.content), gear and {itemsOnly = true} or nil)
    self:TrackField(self.spriteBrowser.search, true)
    self.layout = function() self.spriteBrowser:Resize(self.width, self.height) end
    return self
end

function View:Tick()
    if self.spriteBrowser then self.spriteBrowser:Tick() end
end

function View:Destroy(detached)
    if self.destroyed then return end
    if self.spriteBrowser then self.spriteBrowser:Destroy(detached); self.spriteBrowser = nil end
    Base.Destroy(self, detached)
end

return View
