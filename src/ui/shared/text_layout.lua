local TextLayout = {}

function TextLayout.Lines(text, font, width)
    local lines = {}
    width = math.max(1, width)
    for paragraph in (text:gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in paragraph:gmatch("%s*%S+") do
            if font:GetStringWidth(line .. word, true) <= width then
                line = line .. word
            else
                if line ~= "" then lines[#lines + 1] = line; line = "" end
                word = word:gsub("^%s+", "")
                for character in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                    if line ~= "" and font:GetStringWidth(line .. character, true) > width then
                        lines[#lines + 1] = line
                        line = ""
                    end
                    line = line .. character
                end
            end
        end
        lines[#lines + 1] = line
    end
    return lines
end

return TextLayout
