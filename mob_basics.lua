
------------------------------------------------------------------------------------------------------
-- Provides basic mob functionality:
------------------------------------------------------------------------------------------------------
-- * handles formspec input of a mob 
-- * allows configuration of the mob
-- * adds spawn command
-- * initializes a mob
-- * helper functions (i.e. turn towards player)
------------------------------------------------------------------------------------------------------

-- TODO: save trader data to a file

minetest.register_privilege("mob_basics_spawn", { description = "allows to spawn mob_basic based mobs with a chat command (i.e. /trader)", give_to_singleplayer = false});

-- reserve namespace for basic mob operations
mob_basics = {}

-- store information about the diffrent mobs
mob_basics.mob_types = {}

-- if you want to add a new texture, do it here
mob_basics.TEXTURES = {'kuhhaendler.png', 'bauer_in_sonntagskleidung.png', 'baeuerin.png', 'character.png', 'wheat_farmer_by_addi.png' };
-- further good looking skins:
--mob_basics.TEXTURES = {'kuhhaendler.png', 'bauer_in_sonntagskleidung.png', 'baeuerin.png', 'character.png', 'wheat_farmer_by_addi.png',
--			"pawel04z.png", "character.png", "skin_2014012302322877138.png",
--			"6265356020613120.png","4535914155999232.png","6046371190669312.png","1280435.png"};

-- TODO: gather textures from installed skin mods?





-----------------------------------------------------------------------------------------------------
-- Logging is important for debugging
-----------------------------------------------------------------------------------------------------
mob_basics.log = function( msg, self, prefix )
	if( self==nil ) then
		minetest.log("action", '[mob_basics] '..tostring( msg ) );
	else
		minetest.log("action", '[mob_basics] '..tostring( msg )..
			' id:'..tostring(               self[ prefix..'_id'] )..
			' typ:'..tostring(              self[ prefix..'_typ'] or '?' )..
			' prefix:'..tostring(           prefix or '?' )..
			' at:'..minetest.pos_to_string( self.object:getpos() )..
			' by:'..tostring(               self[ prefix..'_owner'] )..'.');
	end
end



-----------------------------------------------------------------------------------------------------
-- return a list of all known mob types which use prefix 
-----------------------------------------------------------------------------------------------------
mob_basics.type_list_for_prefix = function( prefix )
	local list = {};
	if( not( prefix ) or not( mob_basics.mob_types[ prefix ] )) then
		return list;
	end
	for k,v in pairs( mob_basics.mob_types[ prefix ] ) do
		table.insert( list, k );
	end
	return list;
end





-----------------------------------------------------------------------------------------------------
-- idea taken from npcf
-----------------------------------------------------------------------------------------------------
mob_basics.find_mob_by_id = function( id, prefix )

	if( not( id )) then
		return;
	end

	for i, v in pairs( minetest.luaentities ) do
		if( v.object and v[ prefix..'_typ'] and v[ prefix..'_id'] and v[ prefix..'_id'] == id ) then
			return v;
		end
	end
end


-----------------------------------------------------------------------------------------------------
-- helper function that lets the mob turn towards a target; taken from npcf
-----------------------------------------------------------------------------------------------------
mob_basics.get_face_direction = function(v1, v2)
        if v1 and v2 then
                if v1.x and v2.x and v1.z and v2.z then
                        dx = v1.x - v2.x
                        dz = v2.z - v1.z
                        return math.atan2(dx, dz)
                end
        end
end
-----------------------------------------------------------------------------------------------------
-- turn towards the player
-----------------------------------------------------------------------------------------------------
mob_basics.turn_towards_player = function( self, player )
	if( self.object and self.object.setyaw ) then
		self.object:setyaw( mob_basics.get_face_direction( self.object:getpos(), player:getpos() ));
	end
end



-----------------------------------------------------------------------------------------------------
-- the mobs can vary in height and width
-----------------------------------------------------------------------------------------------------
-- create pseudoradom gaussian distributed numbers
mob_basics.random_number_generator_polar = function()
	local u = 0;
	local v = 0;
	repeat
		u = 2 * math.random() - 1;
		v = 2 * math.random() - 1;
		q = u * u + v * v
	until( (0 < q) and (q < 1));

	p = math.sqrt(-2 * math.log(q) / q) -- math.log returns ln(q)
	return {x1 = u * p, x2 = v * p };
end

-----------------------------------------------------------------------------------------------------
-- visual_size needs to be updated whenever changed or the mob is activated
-----------------------------------------------------------------------------------------------------
-- called whenever changed/configured;
-- called from the entity itself in on_activate;
-- standard size is assumed to be 180 cm
mob_basics.update_visual_size = function( self, new_size, generate, prefix )
	if( not( new_size ) or not( new_size.x )) then
		if( generate ) then
			local res = mob_basics.random_number_generator_polar();
			local width  = 1.0+(res.x1/20.0);
			local height = 1.0+(res.x2/10.0);
			width  = math.floor( width  * 100 + 0.5 );
			height = math.floor( height * 100 + 0.5 );
			new_size = {x=(width/100.0), y=(height/100.0), z=(width/100.0)};
		else
			new_size = {x=1, y=1, z=1};
		end
	end
	if( not( self[ prefix..'_vsize'] ) or not(self[ prefix..'_vsize'].x)) then
		self[ prefix..'_vsize'] = {x=1, y=1, z=1};
	end
	self[ prefix..'_vsize'].x = new_size.x;
	self[ prefix..'_vsize'].y = new_size.y;
	self[ prefix..'_vsize'].z = new_size.z;
	self.object:set_properties( { visual_size  = {x=self[ prefix..'_vsize'].x, y=self[ prefix..'_vsize'].y, z=self[ prefix..'_vsize'].z}});
end


-----------------------------------------------------------------------------------------------------
-- configure a mob using a formspec menu
-----------------------------------------------------------------------------------------------------
mob_basics.config_mob = function( self, player, menu_path, prefix, formname, fields )

	-- change texture
	if( menu_path and #menu_path>3 and menu_path[2]=='config' and menu_path[3]=='texture' ) then
		local nr = tonumber( menu_path[4] );
		-- actually set the new texture
		if( nr and nr > 0 and nr <= #mob_basics.TEXTURES ) then
			self[ prefix..'_texture'] = mob_basics.TEXTURES[ nr ];
			self.object:set_properties( { textures = { self[ prefix..'_texture'] }});
		end

	-- change animation (i.e. sit, walk, ...)
	elseif( menu_path and #menu_path>3 and menu_path[2]=='config' and menu_path[3]=='anim' ) then
		self[ prefix..'_animation'] = menu_path[4];
		self.object:set_animation({x=self.animation[ self[ prefix..'_animation']..'_START'], y=self.animation[ self[ prefix..'_animation']..'_END']},
				self.animation_speed-5+math.random(10));
	end

	
	-- texture and animation are changed via buttons; the other options use input fields
	-- prepare variables needed for the size of the mob and the actual formspec
	local formspec = 'size[10,8]'; 
	fields['MOBheight'] = tonumber( fields['MOBheight']);
	fields['MOBwidth']  = tonumber( fields['MOBwidth']);

	if( not( self[ prefix..'_vsize'] ) or not( self[ prefix..'_vsize'].x )) then
		self[ prefix..'_vsize'] = {x=1,y=1,z=1};
	end
	-- rename a mob
	if( fields['MOBname'] and fields['MOBname'] ~= "" and fields['MOBname'] ~= self[ prefix..'_name'] ) then
		minetest.chat_send_player( player:get_player_name(),
			'Your mob has been renamed from \"'..tostring( self[ prefix..'_name'] )..'\" to \"'..
			fields['MOBname']..'\".');
		self[ prefix..'_name'] = fields['MOBname'];
		formspec = formspec..'label[3.0,1.5;Renamed successfully.]';

	-- height has to be at least halfway reasonable
	elseif( fields['MOBheight'] and fields['MOBheight']>20 and fields['MOBheight']<300 
		and (fields['MOBheight']/180.0)~=self[ prefix..'_vsize'].y ) then

		local new_height = math.floor((fields['MOBheight']/1.8) +0.5)/100.0;
		mob_basics.update_visual_size( self, {x=self[ prefix..'_vsize'].x, y=new_height, z=self[ prefix..'_vsize'].z}, false, prefix );
		formspec = formspec..'label[3.0,1.5;Height changed to '..tostring( self[ prefix..'_vsize'].y*180)..' cm.]';

	-- width (x and z direction) has to be at least halfway reasonable
	elseif( fields['MOBwidth'] and fields['MOBwidth']>50 and fields['MOBwidth']<150 
		and (fields['MOBwidth']/100.0)~=self[ prefix..'_vsize'].x ) then

		local new_width  = math.floor(fields['MOBwidth'] +0.5)/100.0;
		mob_basics.update_visual_size( self, {x=new_width, y=self[ prefix..'_vsize'].y, z=new_width}, false, prefix );
		formspec = formspec..'label[3.0,1.5;Width changed to '..tostring( self[ prefix..'_vsize'].x*100)..'%.]';
	end

	local npc_id = self[ prefix..'_id'];
	formspec = formspec..
		'label[3.0,0.0;Configure your mob]'..
		'label[0.0,0.5;Activity:]'..
		'button[1.5,0.6;1,0.5;'..npc_id..'_config_anim_stand;*stand*]'..
		'button[2.5,0.6;1,0.5;'..npc_id..'_config_anim_sit;*sit*]'..
		'button[3.5,0.6;1,0.5;'..npc_id..'_config_anim_sleep;*sleep*]'..
		'button[4.5,0.6;1,0.5;'..npc_id..'_config_anim_walk;*walk*]'..
		'button[5.5,0.6;1,0.5;'..npc_id..'_config_anim_mine;*mine*]'..
		'button[6.5,0.6;1,0.5;'..npc_id..'_config_anim_walkmine;*w&m*]'..
		'label[0.0,1.0;Name of the mob:]'..
		'field[3.0,1.5;3.0,0.5;MOBname;;'..( self[ prefix..'_name'] or '?' )..']'..
		'label[5.8,1.0;Height:]'..
		'field[6.8,1.5;0.9,0.5;MOBheight;;'..( self[ prefix..'_vsize'].y*180)..']'..
		'label[7.2,1.0;cm]'..
		'label[5.8,1.5;Width:]'..
		'field[6.8,2.0;0.9,0.5;MOBwidth;;'..( (self[ prefix..'_vsize'].x*100) or '100' )..']'..
		'label[7.2,1.5;%]'..
		'label[0.0,1.6;Select a texture:]'..
		'button_exit[7.5,0.2;2,0.5;'..npc_id..'_take;Take]'..
		'button[7.5,0.7;2,0.5;'..npc_id..'_main;Back]'..
		'button[7.5,1.2;2,0.5;'..npc_id..'_config_store;Store]';

	-- list available textures and mark the currently selected one
	for i,v in ipairs( mob_basics.TEXTURES ) do
		local label = '';
		if( v==self[ prefix..'_texture'] ) then
			label = 'current';
		end
		formspec = formspec..
			'image_button['..tostring((i%8)*1.1-1.0)..','..tostring(math.ceil(i/8)*1.1+1.2)..
					';1.0,1.0;'..v..';'..npc_id..'_config_texture_'..tostring(i)..';'..label..']';
	end

	-- show the resulting formspec to the player
	minetest.show_formspec( player:get_player_name(), formname, formspec );
end





-----------------------------------------------------------------------------------------------------
-- formspec input received
-----------------------------------------------------------------------------------------------------
mob_basics.form_input_handler = function( player, formname, fields)

	-- are we responsible to handle this input?
	if( not( formname ) or formname ~= "mob_trading:trader" ) then -- TODO
		return false;
	end

-- TODO: determine prefix from formname
	prefix = 'trader';

	-- all the relevant information is contained in the name of the button that has
	-- been clicked on: npc-id, selections
	for k,v in pairs( fields ) do

		if( k == 'quit' and #fields==1) then
			return true;
		end

		-- all values are seperated by _
		local menu_path = k:split( '_');
		if( menu_path and #menu_path > 0 ) then
			-- find the mob object
			local self = mob_basics.find_mob_by_id( menu_path[1], prefix );
			if( self ) then
				if( #menu_path == 1 ) then
					menu_path = nil;
				end

				-- pick the mob up
				if( v=='Take' ) then 
					if( mob_pickup and mob_pickup.pick_mob_up ) then
						-- all these mobs do have a unique id and are personalized, so the last parameter is true
						mob_pickup.pick_mob_up(   self, player, menu_path, prefix, true );
					end
					return true;

				-- configure mob (the mob turns towards the player and shows a formspec)
				elseif( v=='Config' or (#menu_path>1 and menu_path[2]=='config')) then
					mob_basics.turn_towards_player(   self, player );
					mob_basics.config_mob(            self, player, menu_path, prefix, formname, fields ); 
					return true;

				-- trade with the mob (who turns towards the player and shows a formspec)
				else
					mob_basics.turn_towards_player(   self, player );
					mob_trading.show_trader_formspec( self, player, menu_path, fields,
									  mob_basics.mob_types[ prefix ][ self.trader_typ ].goods ); -- this is handled in mob_trading.lua
					return true;
				end
				return true;
			end
		end
	end
	return true;
end


-- make sure we receive the input
minetest.register_on_player_receive_fields( mob_basics.form_input_handler );




-----------------------------------------------------------------------------------------------------
-- initialize a newly created mob
-----------------------------------------------------------------------------------------------------
mob_basics.initialize_mob = function( self, mob_name, mob_typ, mob_owner, mob_home_pos, prefix)

	local typ_data = mob_basics.mob_types[ prefix ];

	-- does this typ of mob actually exist?
	if( not( mob_typ ) or not( typ_data ) or not( typ_data[ mob_typ ] )) then
		mob_typ = 'default'; -- a default mob
	end

	-- each mob may have an individual name
	if( not( mob_name )) then
		local i = math.random( 1, #typ_data[ mob_typ ].names ); 
		self[ prefix..'_name'] = typ_data[   mob_typ ].names[ i ];
	else
		self[ prefix..'_name'] = mob_name;
	end

	if( typ_data[ mob_typ ].description ) then
		self.description = typ_data[ mob_typ ].description; 
	else
		self.description = prefix..' '..self[ prefix..'_name'];
	end

	self[ prefix..'_typ']       = mob_typ;      -- the type of the mob
	self[ prefix..'_owner']     = mob_owner;    -- who spawned this guy?
	self[ prefix..'_home_pos']  = mob_home_pos; -- position of a control object (build chest, sign?)
	self[ prefix..'_pos']       = self.object:getpos(); -- the place where the mob was "born"
	self[ prefix..'_birthtime'] = os.time();       -- when was the npc first called into existence?
	self[ prefix..'_sold']      = {};              -- the trader is new and had no time to sell anything yet (only makes sense for traders)

	mob_basics.update_visual_size( self, nil, true, prefix ); -- generate random visual size

-- TODO: select a better uniq_id (i.e. time incl. microseconds)
	-- create unique ID for this trader; floor is used to make the ID shorter (two mobs at the
	-- same place would be confusing anyway)
	local uniq_id = minetest.pos_to_string( {
				x=math.floor(self[ prefix..'_pos'].x),
				y=math.floor(self[ prefix..'_pos'].y),
				z=math.floor(self[ prefix..'_pos'].z)
			})..'-'..self.trader_name;

	-- mobs flying in the air would be odd
	self.object:setvelocity(    {x=0, y=  0, z=0});
	self.object:setacceleration({x=0, y=-10, z=0});


	-- if there is already a mob with the same id, remove this one here in order to avoid duplicates
	if( mob_basics.find_mob_by_id( uniq_id, prefix )) then

		self.object:remove();
		return false;
	else
		self[ prefix..'_id'] = uniq_id;
		return true;
	end
end


-----------------------------------------------------------------------------------------------------
-- spawn a mob
-----------------------------------------------------------------------------------------------------
mob_basics.spawn_mob = function( pos, mob_typ, player_name, mob_entity_name, prefix, initialize )

	-- slightly above the position of the player so that it does not end up in a solid block
	local object = minetest.env:add_entity( {x=pos.x, y=(pos.y+1.5), z=pos.z}, mob_entity_name );
	if( not( initialize )) then
		return;
	end
	if object ~= nil then
		object:setyaw( -1.14 );
		local self = object:get_luaentity();
		if( mob_basics.initialize_mob( self, nil, mob_typ, player_name, pos, prefix )) then

			mob_basics.log( 'Spawned mob', self, prefix );
			self[ prefix..'_texture'] = mob_basics.TEXTURES[ math.random( 1, #mob_basics.TEXTURES )];
			self.object:set_properties( { textures = { self[ prefix..'_texture'] }});
		else
			mob_basics.log( 'Error: ID already taken. Can not spawn mob.', nil, prefix );
		end
	end
end

-- compatibility function for random_buildings
mobf_trader_spawn_trader = mob_basics.spawn_mob;


-----------------------------------------------------------------------------------------------------
-- handle input from a chat command to spawn a mob
-----------------------------------------------------------------------------------------------------
mob_basics.handle_chat_command = function( name, param, prefix, mob_entity_name )

	if( param == "" or param==nil) then
		minetest.chat_send_player(name,
			"Please supply the type of "..prefix.."! Supported: "..
			table.concat( mob_basics.type_list_for_prefix( prefix ), ', ')..'.' ); 
		return;
	end
                
	if( not( mob_basics.mob_types[ prefix ] ) or not( mob_basics.mob_types[ prefix ][ param ] )) then 
		minetest.chat_send_player(name,
			"A mob "..prefix.." of type \""..tostring( param )..
			"\" does not exist. Supported: "..
			table.concat( mob_basics.type_list_for_prefix( prefix ), ', ')..'.' );
		return;
	end

	-- the actual spawning requires a priv; the type list as such may be seen by anyone
	if( not( minetest.check_player_privs(name, {mob_basics_spawn=true}))) then 
		minetest.chat_send_player(name,
			"You need the mob_basics_spawn priv in order to spawn "..prefix.."."); 
		return;
	end

	local player = minetest.env:get_player_by_name(name);
	local pos    = player:getpos();

	minetest.chat_send_player(name,
		"Placing "..prefix.." \'"..tostring( param )..
		"\' at your position: "..minetest.pos_to_string( pos )..".");
	mob_basics.spawn_mob( pos, param, name, mob_entity_name, prefix, true );
end

