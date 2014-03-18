
--[[
Features:
 * supports up to 16 different trade offers (for more, space might get too tight in the formspec)
 * up to three diffrent payments can be offered per trade offer (if more, space might get too tight in the formspec)
 * one offer (either what the trader offers or what he requests as price) may consist of up to four diffrent stacks
 * trader types can be pre-defined; each trader of that type will then sell the same goods for the same prices
 * individual traders have their own set of trade offers:
   add, edit and delete is supported for trade offers
 * traders can be spawned with the chatcommand "/trader <type>", i.e. "/trader individual";
   the trader_spawn priv is needed in order to use that chat command
 * traders can be picked up, added to your inventory, carried to another place and be placed there;
   it requires the trader_take priv or ownership of that particular trader ('.. is my employer') and is offered in the trader's formspec 
 * supports money  mod: use mobf_trader:money as item name for money and stack size for actual price
 * supports money2 mod: use mobf_trader:money2 as item name and stack size for actual price
 * no media data required other than skins for the traders; the normal player-model is used
 * traders only do something if you right-click them and call up their offer, so they do not require many ressources
 * the formspec could also be used by i.e. trade chests (mobs are more decorative!)
--]]
 

-- TODO: add a better texture
-- TODO: produce a bench occasionally and sit down on it; pick up bench when getting up
-- TODO: move relevant code into extra file
-- TODO: rename mod?
-- TODO: limit offer to x items/hour?


-- TODO: accept group:bla for prices as well? could be very practical!
-- TODO: save trader data to a file
mobf_trader = {}

mobf_trader.npc_trader_data = {}


mobf_trader.TEXTURES = {'kuhhaendler.png', 'bauer_in_sonntagskleidung.png', 'baeuerin.png' };
-- further good looking skins:
--mobf_trader.TEXTURES = {'kuhhaendler.png', 'bauer_in_sonntagskleidung.png', 'baeuerin.png',
--			"pawel04z.png", "character.png", "skin_2014012302322877138.png",
--			"6265356020613120.png","4535914155999232.png","6046371190669312.png","1280435.png"};



minetest.register_privilege("trader_spawn", { description = "allows to spawn mobf_traders with the /trader command", give_to_singleplayer = false});
minetest.register_privilege("trader_take",  { description = "allows to pick up mobf_traders that are not your own", give_to_singleplayer = false});


dofile(minetest.get_modpath("mobf_trader").."/mob_trading.lua");   -- the actual trading code - complete with formspecs

mobf_trader.log = function( msg, self )
	if( self==nil ) then
		minetest.log("action", '[mobf_trader] '..tostring( msg ) );
	else
		minetest.log("action", '[mobf_trader] '..tostring( msg )..
			' trader id:'..tostring(        self.trader_id )..
			' typ:'..tostring(              self.trader_typ or '?' )..
			' at:'..minetest.pos_to_string( self.trader_pos )..
			' by:'..tostring(               self.trader_owner )..'.');
	end
end


-- helper function that lets the mob turn towards a target; taken from npcf
mobf_trader.get_face_direction = function(v1, v2)
        if v1 and v2 then
                if v1.x and v2.x and v1.z and v2.z then
                        dx = v1.x - v2.x
                        dz = v2.z - v1.z
                        return math.atan2(dx, dz)
                end
        end
end

-- return a list of all known trader types
mobf_trader.npc_trader_type_list = function()

	local list = {};
	for k,v in pairs( mobf_trader.npc_trader_data ) do
		table.insert( list, k );
	end
	return list;
end


-- diffrent types of traders trade diffrent goods, have diffrent name lists etc.
mobf_trader.add_trader = function( prototype, description, speciality, goods, names, texture )

	-- default texture/skin for the trader
	if( not(texture) or (texture == "" )) then
		texture = "character.png";
	end

	mobf_trader.log('Adding trader typ '..speciality, nil );


	mobf_trader.npc_trader_data[ speciality ] = {
		description = description,
		speciality  = speciality,
		goods       = goods,
		names       = names,
		texture     = texture
	}
end

-- this trader can be configured by a player or admin
mobf_trader.add_trader( nil, 'Trader who is working for someone', 'individual', {}, {'nameless'}, {} );


-- idea taken from npcf
mobf_trader.find_trader_by_id = function( id )

	if( not( id )) then
		return;
	end

	for i, v in pairs( minetest.luaentities ) do
		if( v.object and v.trader_typ and v.trader_id and v.trader_id == id ) then
			return v;
		end
	end
end









-----------------------------------------------------------------------------------------------------
-- pick the trader up and store in the players inventory;
-----------------------------------------------------------------------------------------------------
-- the traders data will be saved and he can be placed at another location
mobf_trader.pick_trader_up     = function( self, player, menu_path )

	if( not( self ) or not( player )) then
		return;
	end

	-- check the privs again to be sure that there's no maliscious client input
	if( not( (self.trader_owner and self.trader_owner == player:get_player_name())
	       or minetest.check_player_privs( player:get_player_name(), {trader_take=true}))) then

		minetest.chat_send_player( player:get_player_name(),
			'You do not own this trader and do not have the trader_take priv. Taking failed.');
		return;
	end


	local staticdata = self:get_staticdata();

	-- deserialize to do some tests
	local staticdata_table = minetest.deserialize( staticdata );
	if(    not( staticdata_table.trader_name )
	    or not( staticdata_table.trader_id )
	    or not( staticdata_table.trader_typ )
	    or not( mobf_trader.npc_trader_data[ staticdata_table.trader_typ ] )) then

		minetest.chat_send_player( player:get_player_name(),
			'This trader is misconfigured. Please punch him in order to remove him.');
		return;
	end


	local player_inv = player:get_inventory();

	-- no point in doing more if the player can't take the trader due to too few space
	if( not( player_inv:room_for_item("main", 'mobf_trader:trader_item' ))) then
		minetest.chat_send_player( player:get_player_name(),
			'You do not have a free inventory space for the trader. Taking failed.');
		return;
	end


	-- create a stack with a general trader item
	local trader_as_item = ItemStack( 'mobf_trader:trader_item' );

	-- turn that stack data into a form we can manipulate
	local item           = trader_as_item:to_table();
	-- the metadata field became available - it now stores the real data
	item[ "metadata" ]   = staticdata;
	-- save the changed table
	trader_as_item:replace( item );


	minetest.chat_send_player( player:get_player_name(),
		'Trader picked up. In order to use him again, just wield him and place him somewhere.');

	mobf_trader.log( player:get_player_name()..' picked up', self );

	-- put the trader into the players inventory
	player_inv:add_item( "main", trader_as_item );
	-- remove the now obsolete trader
	self.object:remove();
end




-----------------------------------------------------------------------------------------------------
-- set name and texture of a trader
-----------------------------------------------------------------------------------------------------
mobf_trader.config_trader = function( self, player, menu_path, fields, menu_path )

	if( menu_path and #menu_path>3 and menu_path[2]=='config' and menu_path[3]=='texture' ) then
		local nr = tonumber( menu_path[4] );
		-- actually set the new texture
		if( nr and nr > 0 and nr <= #mobf_trader.TEXTURES ) then
			self.trader_texture = mobf_trader.TEXTURES[ nr ];
			self.object:set_properties( { textures = { self.trader_texture }});
		end
	end

	local formspec = 'size[10,8]'; 

	-- rename a trader
	if( fields['tradername'] and fields['tradername'] ~= "" and fields['tradername'] ~= self.trader_name ) then
		minetest.chat_send_player( player:get_player_name(),
			'Your trader has been renamed from \"'..tostring( self.trader_name )..'\" to \"'..
			fields['tradername']..'\".');
		self.trader_name = fields['tradername'];
		formspec = formspec..'label[3.0,1.5;Renamed successfully.]';
	end

	local npc_id = self.trader_id;
	formspec = formspec..
		'label[3.0,0.0;Configure your trader]'..
		'label[0.0,1.0;Name of the trader:]'..
		'label[0.0,1.6;Select a texture:]'..
		'field[3.0,1.5;3.0,0.5;tradername;;'..( self.trader_name or '?' )..']'..
		'button[7.5,0.5;2,0.5;'..npc_id..'_main;Back]'..
		'button[7.5,1.2;2,0.5;'..npc_id..'_config_store;Store]';

	for i,v in ipairs( mobf_trader.TEXTURES ) do
		local label = '';
		if( v==self.trader_texture ) then
			label = 'current';
		end
		formspec = formspec..
			'image_button['..tostring((i%8)*1.1-1.0)..','..tostring(math.ceil(i/8)*1.1+1.2)..
					';1.0,1.0;'..v..';'..npc_id..'_config_texture_'..tostring(i)..';'..label..']';
	end

	minetest.show_formspec( player:get_player_name(), "mob_trading:trader", formspec );
end



-----------------------------------------------------------------------------------------------------
-- formspec input received
-----------------------------------------------------------------------------------------------------
mobf_trader.form_input_handler = function( player, formname, fields)

	-- are we responsible to handle this input?
	if( not( formname ) or formname ~= "mob_trading:trader" ) then
		return false;
	end

	-- all the relevant information is contained in the name of the button that has
	-- been clicked on: npc-id, selections
	for k,v in pairs( fields ) do

		if( k == 'quit' ) then
			return true;
		end

		-- all values are seperated by _
		local menu_path = k:split( '_');
		if( menu_path and #menu_path > 0 ) then
			-- find the trader object
			local trader = mobf_trader.find_trader_by_id( menu_path[1] );
			if( trader ) then
				if( #menu_path == 1 ) then
					menu_path = nil;
				end
				if( v=='Take' ) then
					mobf_trader.pick_trader_up(       trader, player, menu_path );
					return true;
				elseif( v=='Config' or (#menu_path>1 and menu_path[2]=='config')) then
					mobf_trader.config_trader(        trader, player, menu_path, fields, menu_path );
					return true;
				else
					mob_trading.show_trader_formspec( trader, player, menu_path, fields ); -- this is handled in mob_trading.lua
					return true;
				end
				return true;
			end
		end
	end
	return true;
end


-- make sure we receive the input
minetest.register_on_player_receive_fields( mobf_trader.form_input_handler );



-----------------------------------------------------------------------------------------------------
-- initialize a newly created trader
-----------------------------------------------------------------------------------------------------
mobf_trader.initialize_trader = function( self, trader_name, trader_typ, trader_owner, trader_home_pos)

	-- does this typ of trader actually exist?
	if( not( trader_typ ) or not( mobf_trader.npc_trader_data[ trader_typ ] )) then
		trader_typ = 'misc'; -- a default trader
	end


	-- each trader may have an individual name
	if( not( trader_name )) then
		local i = math.random( 1, #mobf_trader.npc_trader_data[ trader_typ ].names );
		self.trader_name = mobf_trader.npc_trader_data[ trader_typ ].names[ i ];
	else
		self.trader_name = trader_name;
	end

	if( mobf_trader.npc_trader_data[ trader_typ ].description ) then
		self.description = mobf_trader.npc_trader_data[ trader_typ ].description;
	end

	self.trader_typ       = trader_typ;      -- the type of the trader
	self.trader_owner     = trader_owner;    -- who spawned this guy?
	self.trader_home_pos  = trader_home_pos; -- position of a control object (build chest, sign?)
	self.trader_pos       = self.object:getpos(); -- the place where the trader was "born"
	self.trader_birthtime = os.time();       -- when was the npc first called into existence?
	self.trader_sold      = {};              -- the trader is new and had no time to sell anything yet

	-- create unique ID for this trader; floor is used to make the ID shorter (two mobs at the
	-- same place would be confusing anyway)
	local uniq_id = minetest.pos_to_string( {
				x=math.floor(self.trader_pos.x),
				y=math.floor(self.trader_pos.y),
				z=math.floor(self.trader_pos.z)
			})..'-'..self.trader_name;

	-- traders flying in the air would be odd
	self.object:setvelocity(    {x=0, y=  0, z=0});
	self.object:setacceleration({x=0, y=-10, z=0});


	-- if there is already a mob with the same id, remove this one here in order to avoid duplicates
	if( mobf_trader.find_trader_by_id( uniq_id )) then

		self.object:remove();
		return false;
	else
		self.trader_id = uniq_id;
		return true;
	end
end




mobf_trader.trader_entity_prototype = {

	-- so far, this is more or less the redefinition of the standard player model
	physical     = true,
	collisionbox = {-0.35,-1.0,-0.35, 0.35,0.8,0.35},

	visual       = "mesh";
	visual_size  = {x=1, y=1, z=1},
	mesh         = "character.x",
	textures     = {"character.png"},


	description  = 'Trader',

	-- this mob only has to stand around and wait for customers
        animation = {
                stand_START     =   0,
                stand_END       =  79,
--[[
                sit_START       =  81,
                sit_END         = 160,
                lay_START       = 162,
                lay_END         = 166,
                walk_START      = 168,
                walk_END        = 187,
                mine_START      = 189,
                mine_END        = 198,
                walk_mine_START = 200,
                walk_mine_END   = 219,
--]]
        },
        animation_speed = 30,

        armor_groups = {immortal=1},
	hp_max       = 100, -- just to be sure


	-- specific data for the trader:

	-- individual name (e.g. Fritz or John)
	trader_name      = '',
	-- the goods he sells
	trader_typ       = '',
	-- who has put the trader here? (might be mapgen or a player)
	trader_owner     = '',
	-- where is the build chest or other object that caused this trader to spawn?
	trader_home_pos  = {x=0,y=0,z=0},
	-- at which position has the trader been last?
	trader_pos       = {x=0,y=0,z=0},
	-- when was the NPC first created?
	trader_birthtime = 0,
	-- additional data (perhaps statistics of how much of what has been sold)
	trader_sold      = {},
	-- unique ID for each trader
	trader_id        = '',
	
        decription = "Default NPC",
        inventory_image = "npcf_inv_top.png",


	-- Information that is specific to this particular trader
	get_staticdata = function(self)
		return minetest.serialize( {
				trader_name      = self.trader_name,
				trader_typ       = self.trader_typ,
		                trader_owner     = self.trader_owner, 
		                trader_home_pos  = self.trader_home_pos,
				trader_pos       = self.trader_pos,
		                trader_birthtime = self.trader_birthtime,
		                trader_sold      = self.trader_sold, 
				trader_id        = self.trader_id,
				trader_texture   = self.trader_texture,
				trader_goods     = self.trader_goods,
				trader_limit     = self.trader_limit,
			});
	end,


	-- Called when the object is instantiated.
	on_activate = function(self, staticdata, dtime_s)
	
		-- do the opposite of get_staticdata
		if( staticdata ) then
			
			local data = minetest.deserialize( staticdata );
			if( data and data.trader_id ~= '') then

				self.trader_name      = data.trader_name;
				self.trader_typ       = data.trader_typ;
		                self.trader_owner     = data.trader_owner; 
		                self.trader_home_pos  = data.trader_home_pos;
				self.trader_pos       = data.trader_pos;
		                self.trader_birthtime = data.trader_birthtime;
		                self.trader_sold      = data.trader_sold; 
				self.trader_id        = data.trader_id;
				self.trader_texture   = data.trader_texture;
				self.trader_goods     = data.trader_goods;
				self.trader_limit     = data.trader_limit;
			end
	
			if( self.trader_texture ) then
				self.object:set_properties( { textures = { self.trader_texture }});
			end
		end
						
		-- the mob will do nothing but stand around
		self.object:set_animation({x=self.animation.stand_START, y=self.animation.stand_END}, self.animation_speed);

		-- initialize a new trader
		if( not( self.trader_name ) or self.trader_name=='' or self.trader_id=='') then
			-- no name supplied - it will be choosen automaticly
			-- TODO: the typ of trader is unknown at this stage
			local typen = mobf_trader.npc_trader_type_list();
			local i     = math.random(1,#typen );
			-- if trader_id is a duplicate, this entity here (self) will be removed
			mobf_trader.initialize_trader( self, nil, typen[ i ], nil, {x=0,y=0,z=0});
		end

		-- the trader has to be subject to gravity
		self.object:setvelocity(    {x=0, y=  0, z=0});
		self.object:setacceleration({x=0, y=-10, z=0});
	end,


-- this mob waits for rightclicks and does nothing else
--[[
	-- Called on every server tick (dtime is usually 0.1 seconds)
	on_step = function(self, dtime)
	end,
--]]

	-- this is a fast way to get rid of obsolete/misconfigured traders
	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)

		if(    not( self.trader_name )
		    or not( self.trader_id )
		    or not( self.trader_typ )
		    or not( mobf_trader.npc_trader_data[ self.trader_typ ] )) then

			self.object:remove();
		else
			self.hp_max = 100;
		end
		-- prevent accidental (or purposeful!) kills
		self.object:set_hp( self.hp_max );
		-- talk to the player
		if( puncher and puncher:get_player_name() ) then
			minetest.chat_send_player( puncher:get_player_name(),
				'Hey! Stop doing that. I am a peaceful trader. Here, buy something:');
			-- marketing - if *that* doesn't disencourage aggressive players... :-)
			mob_trading.show_trader_formspec( self, puncher, nil, nil ); -- this is handled in mob_trading.lua
		end
	end,


	-- show the trade menu
	on_rightclick = function(self, clicker)

		if( not( self) or not( clicker )) then
			return;
		end

		mob_trading.show_trader_formspec( self, clicker, nil, nil ); -- this is handled in mob_trading.lua
	end,
}


minetest.register_entity( "mobf_trader:trader", mobf_trader.trader_entity_prototype);



minetest.register_craftitem("mobf_trader:trader_item", {
	name            = "Trader",
	description     = "Trader. Place him somewhere to activate.",
	groups          = {},
	inventory_image = "character.png",
	wield_image     = "character.png",
	wield_scale     = {x=1,y=1,z=1},
	-- carries individual metadata - stacking would interfere with that
	stack_max = 1,

	on_place = function( itemstack, placer, pointed_thing )

		if( not( pointed_thing ) or pointed_thing.type ~= "node" ) then
			minetest.chat_send_player( placer:get_player_name(),
				'Error: No node selected for trader to spawn on. Cannot spawn him.');
			return itemstack; 
		end

		local item = itemstack:to_table();
		if( not( item[ "metadata"] ) or item["metadata"]=="" ) then
			minetest.chat_send_player( placer:get_player_name(),
				'Error: Trader is not properly configured. Cannot spawn him.');
			return itemstack; 
		end

		local data = minetest.deserialize( item[ "metadata" ]);
		if( not( data ) or data.trader_id == '') then
			minetest.chat_send_player( placer:get_player_name(),
				'Error: Trader is misconfigured. Cannot spawn him.');
			return itemstack;
		end

		-- if there is already a mob with the same id, do not create a new one
		if( mobf_trader.find_trader_by_id( data.trader_id )) then

			minetest.chat_send_player( placer:get_player_name(),
				'A trader with that ID exists already. Please destroy this duplicate!');
			return itemstack;
		end


		local pos  = minetest.get_pointed_thing_position( pointed_thing, above );

		-- spawn a trader
		local object = minetest.env:add_entity( {x=pos.x, y=(pos.y+1.5), z=pos.z}, "mobf_trader:trader" );
		if( not( object )) then
			minetest.chat_send_player( placer:get_player_name(),
				'Error: Spawning of trader failed.');
			return itemstack;
		end
			
		object:setyaw( -1.14 );

		local self = object:get_luaentity();

		-- transfer the data to the trader object
		self.trader_name      = data.trader_name;
		self.trader_typ       = data.trader_typ;
		self.trader_owner     = data.trader_owner; 
		self.trader_home_pos  = data.trader_home_pos;
		self.trader_pos       = data.trader_pos;
		self.trader_birthtime = data.trader_birthtime;
		self.trader_sold      = data.trader_sold; 
		self.trader_id        = data.trader_id;
		self.trader_texture   = data.trader_texture;
		self.trader_goods     = data.trader_goods;
		self.trader_limit     = data.trader_limit;
		self.object:set_properties( { textures = { data.trader_texture }});

		-- the trader was placed at a new location
		self.trader_pos       = pos;

		minetest.chat_send_player( placer:get_player_name(),'Trader placed.');

		mobf_trader.log( placer:get_player_name()..' placed', self );
		return '';
	end,
})










-- spawn a trader
mobf_trader.spawn_trader = function( pos, trader_typ, owner_name )

	-- slightly above the position of the player so that it does not end up in a solid block
	local object = minetest.env:add_entity( {x=pos.x, y=(pos.y+1.5), z=pos.z}, "mobf_trader:trader" );
	if object ~= nil then
		object:setyaw( -1.14 );
		local self = object:get_luaentity();
		if( mobf_trader.initialize_trader( self, nil, trader_typ, owner_name, pos)) then

			mobf_trader.log( 'Spawned trader', self );
			self.trader_texture = mobf_trader.TEXTURES[ math.random( 1, #mobf_trader.TEXTURES )];
			self.object:set_properties( { textures = { self.trader_texture }});
		else
			mobf_trader.log( 'Error: ID already taken. Could not spawn trader.', nil );
		end
	end
end


-- so that this function can be called even when mobf_trader has not been loaded
mobf_trader_spawn_trader = mobf_trader.spawn_trader;


-- add command so that a trader can be spawned
minetest.register_chatcommand("trader", {
	params = "<trader type>",
	description = "Spawns an npc trader of the given type.",
	privs = {},
	func = function(name, param)

		local params_expected = "<trader type>";
		if( param == "" or param==nil) then
			minetest.chat_send_player(name,
				"Please supply the type of trader! Supported: "..
				table.concat( mobf_trader.npc_trader_type_list(), ', ')..'.' );
			return;
		end
                
		if( not( mobf_trader.npc_trader_data[ param ] )) then
			minetest.chat_send_player(name,
				"A trader of type \""..tostring( param )..
				"\" does not exist. Supported: "..
				table.concat( mobf_trader.npc_trader_type_list(), ', ')..'.' );
			return;
		end

		-- the actual spawning requires a priv; the trader list as such may be seen by anyone
		if( not( minetest.check_player_privs(name, {trader_spawn=true}))) then
			minetest.chat_send_player(name,
				"You need the trader_spawn priv in order to spawn traders.");
			return;
		end

		local player = minetest.env:get_player_by_name(name);
		local pos    = player:getpos();

		minetest.chat_send_player(name,
			"Placing trader \""..tostring( param )..
			"\"at your position: "..minetest.pos_to_string( pos )..".");
		mobf_trader.spawn_trader( pos, param, name );
	end
});


-- import all the traders; if you do not want any of them, comment out the line representing the unwanted traders (they are only created if their mods exist)

dofile(minetest.get_modpath("mobf_trader").."/trader_misc.lua");      -- trades a mixed assortment
dofile(minetest.get_modpath("mobf_trader").."/trader_clay.lua");      -- no more destroying beaches while digging for clay and sand!
dofile(minetest.get_modpath("mobf_trader").."/trader_moretrees.lua"); -- get wood from moretrees without chopping down trees
dofile(minetest.get_modpath("mobf_trader").."/trader_animals.lua");   -- buy animals - no need to catch them with a lasso
dofile(minetest.get_modpath("mobf_trader").."/trader_farming.lua");   -- they sell seeds and fruits - good against hunger!


-- TODO: default:cactus  default:papyrus and other plants

-- TODO: accept food in general as trade item (accept groups?)

-- TODO: trader foer angeln?
-- TODO: trader fuer moreores (ingots)
-- TODO: bergbau-trader; verkauft eisen und kohle, kauft brot/food/apples
-- TODO: trader fuer homedecor
-- TODO: trader fuer 3dforniture

-- TODO: special trader for seeds
