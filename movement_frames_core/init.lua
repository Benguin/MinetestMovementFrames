-- FRAME MOVER
-- moves a frame in a direction 
-- doesn't move itself
-- can be moved by frames

-- FRAME
-- sticks to all blocks, including other frames
-- each frame side can be made sticky/non-sticky


local MODNAME = 'movement_frames';
local MOD_READABLE_NAME = "Movement Frames"
movement_frames_core = {} -- movers functions / properties



function movement_frames_core.get_modname(return_readable_name)
    if (return_readable_name) then return MOD_READABLE_NAME
    else return MODNAME
    end
end


function movement_frames_core.setting(setting, default)
	if type(default) == "boolean" then
		local read = minetest.settings:get_bool(MODNAME..":"..setting)
		if read == nil then
			return default
		else
			return read
		end
	elseif type(default) == "string" then
		return minetest.settings:get(MODNAME..":"..setting) or default
	elseif type(default) == "number" then
		return tonumber(minetest.settings:get(MODNAME..":"..setting) or default)
    end
end


--TODO remove
function movement_frames_core.get_obj()
    return movement_frames_core
end

function movement_frames_core.log(message, message_type, disable_color) 
    local base_string = string.format("[%s] ", MOD_READABLE_NAME)

    local message_types = {
        error   = "\27[31;1mERROR: \27[0m ",
        warning = "\27[33;1mWarning: \27[0m "
    }
    if (message_type ~= nil and message_types[message_type] ~= nil and disable_color ~= false) then
        base_string = base_string .. message_types[message_type]
    end

    local output = base_string ..  (message or 'nil')
    print(output)
end

function movement_frames_core.dump(object, message_type, disable_color)
    dumped_object = dump(object)

    movement_frames_core.log(dumped_object, message_type, disable_color)
end


function movement_frames_core.register_entity(name, definition)
    minetest.register_entity(MODNAME..":"..name, definition)
end

function movement_frames_core.register_node(name, definition)
    minetest.register_node(MODNAME..":"..name, definition);
end

function movement_frames_core.register_craftitem(name, definition)
    minetest.register_craftitem(MODNAME..":"..name, definition)
end

local function pos_string(pos, print) 
    local result_string = string.format("(x: %d z:%d y:%d)", pos.x, pos.y, pos.z)
    if (print) then 
        print(result_string)
    end

    return result_string
end

local function node_replaceable(name)
	if minetest.registered_nodes[name] then
		return minetest.registered_nodes[name].buildable_to or false
	end

	return false
end

local function on_mvps_move(moved_nodes)
	for _, callback in ipairs(mesecon.on_mvps_move) do
		callback(moved_nodes)
	end
end

-- Convert facedir value to xyz direction.
function movement_frames_core.facedir_to_dir(facedir)
    local dirs = {
        [0] =  {x = 0, y = 1, z = 0},
        [1] =  {x = 0, y = 0, z = 1},
        [2] =  {x = 0, y = 0, z =-1},
        [3] =  {x = 1, y = 0, z = 0},
        [4] =  {x =-1, y = 0, z = 0},
        [5] =  {x = 0, y =-1, z = 0},
    }
    local axisDirection = (facedir -(facedir%4) )/ 4
    return dirs[axisDirection]
end

-- Convert an xyz dir table to a cardinal direction string
-- x is east - west, y is down or up, and z is north - south.
local function dir_to_cardinal(dir)
    local dir_key
    local dir_value
    for k,v in pairs(dir) do
        if v ~= 0 then 
            dir_key = k
            dir_value = v
        end
    end

    if dir_key == 'x' then 
        return  dir_value < 0 and  "east" or "west" 
    elseif dir_key == 'y' then
        return dir_value < 0 and "down" or "up"
    else 
        return dir_value < 0 and "north" or "south"
    end
end movement_frames_core.dir_to_cardinal = dir_to_cardinal

-- Shortcuts for sanity
local directions = {
    ['+x'] = {x = 1, y = 0, z = 0},
    ['-x'] = {x =-1, y = 0, z = 0},
    ['+y'] = {x = 0, y = 1, z = 0},
    ['-y'] = {x = 0, y =-1, z = 0},
    ['+z'] = {x = 0, y = 0, z = 1},
    ['-z'] = {x = 0, y = 0, z =-1},
}


-- Map rotation and direction to xyz direction
axisDirs = {
    [0] = {
        [0] = directions['+z'],
        [1] = directions['+x'],
        [2] = directions['-z'],
        [3] = directions['-x'],
    },
    [1] = {
        [0] = directions['-y'],
        [1] = directions['+x'],
        [2] = directions['+y'],
        [3] = directions['-x'],
    },
    [2] = {
        [0] = directions['+y'],
        [1] = directions['+x'],
        [2] = directions['-y'],
        [3] = directions['-x'],
    },
    [3] = {
        [0] = directions['+z'],
        [1] = directions['-y'],
        [2] = directions['-z'],
        [3] = directions['+y'],
    },
    [4] = {
        [0] = directions['+z'],
        [1] = directions['+y'],
        [2] = directions['-z'],
        [3] = directions['-y'],
    },
    [5] = {
        [0] = directions['+z'],
        [1] = directions['-x'],
        [2] = directions['-z'],
        [3] = directions['+x'],
    },
}






-- New code for advanced movers

-- Get the full structure to move 
function movement_frames_core.mvps_get_structure(pos, dir, maximum, all_pull_sticky)
	-- determine the number of nodes to be pushed
    local nodes = {}

    local start_pos = {
        x = pos.x,
        z = pos.z ,
        y = pos.y,
    };

	local frontiers = {start_pos}
    
    local start_node = minetest.get_node(start_pos)

    --Movers can only move frames, if the first block isn't a frame, return.
    local can_move_any  = movement_frames_core.setting('can_move_any', false)
    local is_frame = start_node.name == MODNAME..":frame"

    if (not can_move_any and  not is_frame) then return nodes end
    

    -- Get attached blocks
	while #frontiers > 0 do
		local np = frontiers[1]
        local nn = minetest.get_node(np)
        
        --if not empty air
        if not node_replaceable(nn.name) then
            
            --add node to move list
			table.insert(nodes, {node = nn, pos = np})
            if #nodes > maximum then return nil end

			-- add connected nodes to frontiers, connected is a vector list
			-- the vectors must be absolute positions
            local connected = {}
            
            if minetest.registered_nodes[nn.name] and minetest.registered_nodes[nn.name].mvps_sticky 
            then
				connected = minetest.registered_nodes[nn.name].mvps_sticky(np, nn)
			end

            -- movement_frames_core.dump(np)
            -- movement_frames_core.dump(dir)
			table.insert(connected, vector.add(np, dir))

			-- If adjacent node is sticky block and connects add that
			-- position to the connected table
			for _, r in ipairs(mesecon.rules.alldirs) do
				local adjpos = vector.add(np, r)
                local adjnode = minetest.get_node(adjpos)
                
                if minetest.registered_nodes[adjnode.name] and minetest.registered_nodes[adjnode.name].mvps_sticky 
                then
                    local sticksto = minetest.registered_nodes[adjnode.name].mvps_sticky(adjpos, adjnode)

					-- connects to this position?
					for _, link in ipairs(sticksto) do
						if vector.equals(link, np) then
							table.insert(connected, adjpos)
						end
					end
				end
			end

			if all_pull_sticky then
				table.insert(connected, vector.subtract(np, dir))
			end

			-- Make sure there are no duplicates in frontiers / nodes before
			-- adding nodes in "connected" to frontiers
			for _, cp in ipairs(connected) do
                local duplicate = false
                
				for _, rp in ipairs(nodes) do
					if vector.equals(cp, rp.pos) then
						duplicate = true
					end
                end
                
				for _, fp in ipairs(frontiers) do
					if vector.equals(cp, fp) then
						duplicate = true
					end
                end
                
				if not duplicate then
					table.insert(frontiers, cp)
				end
			end
		end
		table.remove(frontiers, 1)
    end

	return nodes
end

-- Accept inventory ref, return ref of copied inventory
function inventory_to_table(inventory) 
    local inv = {}
    local lists = inventory:get_lists()
    if (lists) then
        for listname, stacks in pairs(lists) do
            inv[listname] = {
                size= 1,
                contents={}
            }
            inv[listname].size= inventory:get_size(listname)
            -- movement_frames_core.log(listname, 'error')
            -- movement_frames_core.dump(stacks, 'error')
            for index, stack in ipairs(stacks) do
                -- movement_frames_core.log(index, 'error')
                -- movement_frames_core.dump(stack, 'error')
                local stack_table = stack:to_table()
                -- movement_frames_core.log("STACK TABLE" .. stack:to_string())
                -- movement_frames_core.dump(stack_table, 'error')
                inv[listname].contents[index] = stack_table or {}
            end
        end
    end
    return inv
end

function movement_frames_core.set_inventory_from_table(inventory, table)
    movement_frames_core.dump(table)
    local lists = {}


    for listname, list in ipairs(table) do
        lists[listname] = {}
        for index, stackstring in list.contents do
            lists[listname][index] = ItemStack(stackstring)
        end
        inventory:set_size(listname, list.size)
        
    end
    inventory:set_lists(lists)
end


-- pos: pos of mvps; stackdir: direction of building the stack
-- movedir: direction of actual movement
-- maximum: maximum nodes to be pushed
-- all_pull_sticky: All nodes are sticky in the direction that they are pulled from

function movement_frames_core.move_structure(pos, stackdir, movedir, maximum, all_pull_sticky)
	local nodes = movement_frames_core.mvps_get_structure(pos, movedir, maximum, all_pull_sticky)

	if not nodes then return end
	-- determine if one of the nodes blocks the push / pull
	for id, n in ipairs(nodes) do
		if mesecon.is_mvps_stopper(n.node, movedir, nodes, id) then
			return
		end
	end

	-- remove all nodes
    for _, n in ipairs(nodes) do
        local nmeta =  minetest.get_meta(n.pos)
        local minv = nmeta:get_inventory();
        if (minv) then
            n.inv =  inventory_to_table(minv)
            -- movement_frames_core.log("INVS " .. dump(inv), "warning")
        end

        n.meta = nmeta:to_table()

        --Now we need to copy the inventory; we can't send refs through 
        -- staticdata, so convert it to a table of itemstack strings
        local newInv = {}

        for listname, list in pairs(n.meta.inventory) do
            newInv[listname] = {}
            for key, itemstack in ipairs(list) do
                newInv[listname][key] = itemstack:to_string()
            end
        end

        n.meta.inventory = newInv
    
        local node_timer = minetest.get_node_timer(n.pos)
        if node_timer:is_started() then
            n.node_timer = {node_timer:get_timeout(), node_timer:get_elapsed()}
        end
        minetest.remove_node(n.pos)
      
        
	end

	-- update mesecons for removed nodes ( has to be done after all nodes have been removed )
	for _, n in ipairs(nodes) do
		mesecon.on_dignode(n.pos, n.node)
    end
    
    local should_animate_movement = movement_frames_core.setting('animate_movement', false)

    if (should_animate_movement) then
        -- Add nodes back as node-entities, to visualize movement
        local node_entities = {}
        for _,n in ipairs(nodes) do
            local tile = minetest.registered_nodes[n.node.name].tiles[1]
            local static_data_table = {
                tiles={
                    tile,
                    tile,
                    tile,
                    tile,
                    tile,
                    tile,
                },
                moveDir=movedir,
                pos=pos,
                newPos=vector.add(n.pos, movedir),
                node=n,
                moveStack=nodes
            }
    
            local staticdata = minetest.write_json(static_data_table)
    
            local nEntity = minetest.add_entity(n.pos, MODNAME..":node_entity", staticdata)
            table.insert(node_entities, nEntity)
        end
    else
        -- add nodes back
        for _, n in ipairs(nodes) do
        	local np = vector.add(n.pos, movedir)
    
        	minetest.set_node(np, n.node)
        	minetest.get_meta(np):from_table(n.meta)
        	if n.node_timer then
        		minetest.get_node_timer(np):set(unpack(n.node_timer))
        	end
        end

    end


	local moved_nodes = {}
	local oldstack = mesecon.tablecopy(nodes)
	for i in ipairs(nodes) do
		moved_nodes[i] = {}
		moved_nodes[i].oldpos = nodes[i].pos
		nodes[i].pos = vector.add(nodes[i].pos, movedir)
		moved_nodes[i].pos = nodes[i].pos
		moved_nodes[i].node = nodes[i].node
		moved_nodes[i].meta = nodes[i].meta
		moved_nodes[i].node_timer = nodes[i].node_timer
	end

	on_mvps_move(moved_nodes)

	return true, nodes, oldstack
end


