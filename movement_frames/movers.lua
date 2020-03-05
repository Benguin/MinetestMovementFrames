
local mfcore = movement_frames_core
local timer_interval = mfcore.setting("mover_activation_interval", 0.3)
local mover_speed = mfcore.setting("mover_speed", 1)
local max_push = mfcore.setting("mover_capacity", 500)

function getDirectionToMove(facedir)
    local axisRotation = facedir % 4
    local moverDirection =(facedir-axisRotation) / 4
    return axisDirs[moverDirection][axisRotation]
end


local function move_frames(pos, node, rulename)
    local facingDirection = mfcore.facedir_to_dir(node.param2)  
    local direction = getDirectionToMove(node.param2)
    local frontpos = vector.add(pos, facingDirection)
    
    -- ### Step 1: Push nodes in front ###
    local success, stack, oldstack = mfcore.move_structure(frontpos, direction, direction, max_push)
    if not success then
        minetest.get_node_timer(pos):start(timer_interval)
        return
    end

    -- mesecon.mvps_move_objects(frontpos, direction, oldstack)

    -- ### Step 4: Let things fall ###
    minetest.check_for_falling(vector.add(pos, {x=0, y=1, z=0}))
end


-- REGISTER NODES:

--Mover
mfcore.register_node("mover", {
	tiles = {
		"mover_arrows.png", --y+
		"mover_side.png",
		"mover_side.png",
		"mover_side.png",
		"mover_side.png",
		"mover_side.png",
    },
    is_ground_content = false,
	groups = {cracky = 3},
    description = "Advanced Mover",
    sounds = default.node_sound_stone_defaults(),
    paramtype2 = "facedir",
    on_blast = mesecon.on_blastnode,

    mesecons = {
        effector = {
            action_on = function(pos, node, rulename)
                local node_timer = minetest.get_node_timer(pos)
                if rulename and not node_timer:is_started() then
                    move_frames(pos, node, rulename)
                    node_timer:start(timer_interval)
                end
            end,
            rules = mesecon.rules.default,
        }
    },

    on_rightclick = function(pos, node, player, itemstack, pointed_thing)
        local is_aux_pressed = player.get_player_control(player).aux1
        local facedir = node.param2

        if facedir >= 23 then
            facedir = 0
        elseif is_aux_pressed then
            facedir = facedir-1
        else
            facedir = facedir+1
        end


        minetest.set_node(pos, {
            name   = mfcore.get_modname()..":mover",
            param2 = facedir
        })
    end,

    on_timer = function(pos, elapsed)
		local sourcepos = mesecon.is_powered(pos)
		if not sourcepos then
			return
		end
		local rulename = vector.subtract(sourcepos[1], pos)
		mesecon.activate(pos, minetest.get_node(pos), rulename, 0)
	end,

})



mfcore.register_node("frame", {
    description = "Mover Frame",
    tiles = {
        "mover_frame.png",
        "mover_frame_detail.png",
    },
    drawtype = "glasslike_framed_optional",
    use_texture_alpha = true,
    is_ground_content= false,
    groups = {cracky = 3},

    mvps_sticky = function (pos, node)
        local meta = minetest.get_meta(pos)
        local meta_json = meta:get_string("sticky") 
		local connected = {}
        
        if (meta_json == "") then return connected end

        local sticky = minetest.parse_json(meta_json)
        
        for _, r in ipairs(mesecon.rules.alldirs) do
            local cardinal = mfcore.dir_to_cardinal(r)
            if sticky[cardinal] then
                local blockPos = vector.add(pos, r)
                local node = minetest.get_node(blockPos)
                local moverName = mfcore.get_modname()..":mover"

                if node.name ~= moverName then
                    table.insert(connected, blockPos)
                end
            end
		end
        
        return connected
    end,

    on_construct = function(pos)
        local meta = minetest.get_meta(pos)
        local meta_json = meta:get_string("sticky") 
        local sticky = nil
        if (meta_json ~= "") then 
            sticky = minetest.parse_json(meta_json)
        end
        
        if (sticky == nil) then
            sticky= {
                north = true,
                east  = true,
                south = true,
                west  = true,
                up    = true,
                down  = true,
            }
        end
        meta:set_string("sticky", minetest.write_json(sticky))

    end,

    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        local dir = {
            x= pointed_thing.above.x - pointed_thing.under.x,
            y= pointed_thing.above.y - pointed_thing.under.y,
            z= pointed_thing.above.z - pointed_thing.under.z,
        }
        local cardinal = mfcore.dir_to_cardinal(dir)
        local meta = minetest.get_meta(pos)
        local sticky = minetest.parse_json(meta:get_string("sticky"))

        if itemstack:get_name() == mfcore.get_modname()..":chalk" then
            sticky[cardinal] = false
        elseif itemstack:get_name() == "mesecons:glue" then
            sticky[cardinal] = true
        end
     
        meta:set_string("sticky", minetest.write_json(sticky))
    end
})

mfcore.register_entity("node_entity", {
    visual= "cube",
    -- physical=true,
    visual_size={x=1, y=1},
    textures={
        "AnimatedCyberblock.png",
        "AnimatedCyberblock.png",
        "AnimatedCyberblock.png",
        "AnimatedCyberblock.png",
        "AnimatedCyberblock.png",
        "AnimatedCyberblock.png",
    },
    is_visible=true,
    collisionbox = {
        0.5,
        0.5,
        0.5,
        -0.5,
        -0.5,
        -0.5
    },

    on_activate = function(self, staticdata) 
        local data = minetest.parse_json(staticdata)

        if (not data) then 
            mfcore.log("Imitation Node entity initialised without staticdata", 'error')
            mfcore.dump(staticdata)
            return
        end

        self.data = data

        self.object:set_properties({
            textures=data.tiles,
        })

        self:move_self()
    end,

    move_self= function(self)
        local data = self.data
        local dir = data.moveDir
        self.attached_players = {}
        
        --Blocks per second
        local moveSpeed = vector.multiply(data.moveDir, mover_speed)
        local nodestack = data.moveStack
        local pos = data.pos

        local dir_key
        local dir_value
        local obj_pos = self.object:get_pos()
        
        for key, value in pairs(dir) do
            if value ~= 0 then
                dir_key = key
                dir_value = value
                break
            end
        end

        for k, player in ipairs(minetest.get_connected_players()) do
            local playerPos =  player:get_pos()
            local posDiff = vector.subtract(self.object:get_pos(), playerPos)

            if( math.abs(posDiff.x) <= 0.5 and  math.abs(posDiff.z) <= 0.5)  and posDiff.y > 0.1 and posDiff.y < 3 then
                mfcore.log("Attaching player", player:get_entity_name())
                player:set_attach(self.object, '', {x=posDiff.x, z=posDiff.z, y=posDiff.y+1}, {x=0, y=0, z=0});
                table.insert(self.attached_players, player)
            end
        end
        
        self.dir_value = dir_value;
        self.dir_key = dir_key;

        local np = vector.add(obj_pos, dir)

        -- Move only if destination is not solid or object is inside stack:
        local nn = minetest.get_node(np)
        local node_def = minetest.registered_nodes[nn.name]
        local obj_offset = dir_value * (obj_pos[dir_key] - pos[dir_key])
        if (node_def and not node_def.walkable) or
                (obj_offset >= 0 and
                obj_offset <= #nodestack - 0.5) then
            
            self.object:set_velocity(moveSpeed)

        end
    end,

    -- Become a real block again
    anchor_self= function(self)
        minetest.set_node(self.data.newPos, self.data.node.node)
        local meta = minetest.get_meta(self.data.newPos)
        meta:from_table(self.data.node.meta)

        for k, player in pairs(self.attached_players) do
            player.set_detach()
        end
        self.object:remove()
    end,

    on_step= function(self, time)
        local curPos = self.object:get_pos()
        local sign

        if (not self.data or not self.dir_value ) then return end

        if (self.dir_value < 0) then sign = 1 else sign = -1 end
        
        if (sign == 1) then
            if (curPos[self.dir_key] < self.data.newPos[self.dir_key]) then
                self:anchor_self()
            end
        else 
            if (curPos[self.dir_key] > self.data.newPos[self.dir_key]) then
                self:anchor_self()
            end
        end
    end
})

