local mfcore = movement_frames_core

mfcore.register_craftitem("chalk",{
    description= "Apply to a surface of a frame block to make it non-sticky.",
    inventory_image = "mover_chalk.png",

    on_use = function(itemstack, user, pointed_thing) 
        local item = itemstack:take_item()
        return itemstack
    end,

    on_activate = function(itemstack, user, pointed_thing)
    end,
})