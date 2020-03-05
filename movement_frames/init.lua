local mfcore = movement_frames_core.get_obj()


--List filenames here to load them all
local files = {
    "movers",
    "chalk"
}

for key, file in ipairs(files) do
    dofile(minetest.get_modpath(mfcore.get_modname()).."/"..file..".lua")
end

