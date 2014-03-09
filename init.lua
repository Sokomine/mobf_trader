
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

-- TODO: what about used items? (i.e. almost broken picks...) and other items with individual data
mobf_trader = {}

mobf_trader.npc_trader_data = {}

mobf_trader.MAX_OFFERS             = 24; -- up to that many diffrent offers are supported by the trader of the type 'individual'
mobf_trader.MAX_ALTERNATE_PAYMENTS = 6; -- up to 6 diffrent payments are possible for each good offered

mobf_trader.TEXTURES = {'kuhhaendler.png', 'bauer_in_sonntagskleidung.png', 'baeuerin.png' };
-- further good looking skins:
--mobf_trader.TEXTURES = {'kuhhaendler.png', 'bauer_in_sonntagskleidung.png', 'baeuerin.png',
--			"pawel04z.png", "character.png", "skin_2014012302322877138.png",
--			"6265356020613120.png","4535914155999232.png","6046371190669312.png","1280435.png"};

-- how many nodes does the trader of the type individual search for locked chests?
mobf_trader.LOCKED_CHEST_SEARCH_RANGE = 3;


minetest.register_privilege("trader_spawn", { description = "allows to spawn mobf_traders with the /trader command", give_to_singleplayer = false});
minetest.register_privilege("trader_take",  { description = "allows to pick up mobf_traders that are not your own", give_to_singleplayer = false});


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



-- helper function
mobf_trader.show_trader_formspec_item = function( offset_x, offset_y, stack_desc, nr, prefix, size )

	local stack = ItemStack( stack_desc );
	local anz   = stack:get_count();
	local label = '';
	-- show the label with the amount of item showed only if more than one is sold and the button is large enough
	if( anz > 1 and size>0.7) then
		label = 'label['..(offset_x+0.5*size)..','..(offset_y+0.4*size)..';'..tostring( anz )..'x]';
	else
		label = '';
	end
	
	-- do not show unknown blocks
	if( minetest.registered_items[ stack:get_name()] ) then
-- TODO: tatsaechlich besser so?
if( size>= 1 and false) then
		return	'item_image['..offset_x..','..offset_y..';'..size..','..size..';'..
				( stack:get_name() or '?')..']'..
				label;
end

		return	'item_image_button['..offset_x..','..offset_y..';'..size..','..size..';'..
				( stack:get_name() or '?')..';'..
				prefix..'_'..tostring( nr )..';]'..
				label;
	end
	return '';
end


-- shows up to four items
-- set stretch_x and stretch_y to 0.4 each plus quarter_botton_size to 0.6 in order to make everything fit into one formspec
mobf_trader.show_trader_formspec_item_list = function( offset_x, offset_y, stack_desc, nr, prefix, stretch_x, stretch_y, quarter_button_size )

-- TODO: show "sold out" if no longer availabe?

	-- show multiple items
	if( type( stack_desc )=='table') then

		local formspec = '';
		-- display first image at the lower left corner
		local a = 0;
		local b = 1;

--		formspec = formspec..'label['..(offset_x)..','..(offset_y+0.6)..';Package]';
		-- we can display no more than 4 items
		local k = math.min( 4, #stack_desc );
		-- if there are only 2 items, display them centralized
		if( k==2 ) then
			offset_x = offset_x + 0.5*stretch_x;
		end
			
		for i = 1,k do

			formspec = formspec..
				mobf_trader.show_trader_formspec_item(offset_x+(a*stretch_x), offset_y+(b*stretch_y), stack_desc[i], nr, prefix, quarter_button_size );

			if(    i==1) then a = 1; b = 0; -- 2nd: upper right corner
			elseif(i==2) then a = 1; b = 1; -- 3rd: lower right corner
			elseif(i==3) then a = 0; b = 0; -- 4rd: upper left corner
			end

			-- 2 items: always display centralized
			if( k==2 ) then
				a = 0;
			end
		end
		return formspec;
	else

		-- put the only image we have to display in a central position
		if( quarter_button_size==1 ) then
			offset_x = offset_x + quarter_button_size/2;
			offset_y = offset_y + quarter_button_size/2;
		end

		return mobf_trader.show_trader_formspec_item( offset_x, offset_y, stack_desc, nr, prefix, 1 );
	end
end



-- this is only relevant for the trader of the typ "individual"
-- (that trader uses player-owned chests to store the trade goods)
mobf_trader.show_storage_formspec = function( self, player, menu_path )

	local pos = self.object:getpos();
	local RANGE = mobf_trader.LOCKED_CHEST_SEARCH_RANGE;

	-- search for locked chest from default, locks mod and technic mod chests
	-- ignore technic mithril chests as those are not locked
	local chest_list = minetest.find_nodes_in_area(
		{ x=(pos.x-RANGE), y=(pos.y-RANGE), z=(pos.z-RANGE )},
		{ x=(pos.x+RANGE), y=(pos.y+RANGE), z=(pos.z+RANGE )},
		{'default:chest_locked',        'locks:shared_locked_chest', 
		 'technic:iron_locked_chest',   'technic:copper_locked_chest',
		 'technic:silver_locked_chest', 'technic:gold_locked_chest'});

	local all_chest_inv = {};
	local sum_chest_inv = {};
	for _, p in ipairs( chest_list ) do

		local node  = minetest.get_node( p );
		local meta  = minetest.get_meta( p );
		local owner = meta:get_string( 'owner' );

		if( owner and owner==player:get_player_name() ) then
			
			local inv = meta:get_inventory();

			for i = 1,inv:get_size('main') do

				local stack = inv:get_stack( 'main', i );
				if( not( stack:is_empty() )) then
			
					local stack_name = stack:get_name();
					if( not( sum_chest_inv[ stack_name ] )) then
						sum_chest_inv[ stack_name ] = stack:get_count();
					else
						sum_chest_inv[ stack_name ] = sum_chest_inv[ stack_name ] + stack:get_count();
					end
				end
			end
		end
	end

	for k,v in pairs( sum_chest_inv ) do
		minetest.chat_send_player( player:get_player_name(), 'FOUND '..tostring( k )..' anz:'..tostring( v));
	end
end





mobf_trader.show_trader_formspec = function( self, player, menu_path, fields )

	if( not( self ) or not( player )) then
		return;
	end

	-- turn towards the customer
	self.object:setyaw( mobf_trader.get_face_direction( self.object:getpos(), player:getpos() ));

	local pname = player:get_player_name();

	local npc_id = self.trader_id;
	if( not( npc_id )) then
		return;
	end

	-- which goods does this trader trade?
	local trader_goods = mobf_trader.npc_trader_data[ self.trader_typ ].goods;
	if( self.trader_typ == 'individual' or not( trader_goods ) or #trader_goods < 1 ) then
		trader_goods = self.trader_goods;
		if( not( trader_goods )) then
			trader_goods = {};
		end
	end

	local formspec = 'size[10,11]'..
			 'list[current_player;main;1,7;8,4;]'..
			 'button_exit[7.5,6.3;2,0.5;quit;End trade]';


	-- indicate to the owner of the trader which fields of the owner's inventory are taken as input fields
	-- for trade offers
	if( (self.trader_owner and self.trader_owner == pname ) and self.trader_typ=='individual') then
		formspec = formspec..
			'label[-0.25,6.90;When adding]'..
			'label[-0.25,7.10;new trade,]'..
			'label[-0.25,7.30;suggest this:]'..
			'label[1.1,6.5;Sell:]'..
			'label[2.1,6.5;for:]'..
			-- the Add button is also shown next to the actual trade offers
			'button[9,7.1;1,0.5;'..npc_id..'_add;Add]'; 
		for i = 3, mobf_trader.MAX_ALTERNATE_PAYMENTS do
			formspec = formspec..'label['..(tostring(i)+0.1)..',6.5;or:]';
		end
	end


	-- the player wants to delete a trade offer
	if( menu_path and #menu_path > 1 and menu_path[2]=='delete') then
		if( not(trader_goods )) then
			trader_goods = {};
		end
		local edit_nr = tonumber( menu_path[3] );
		-- store the modified offer
		if( edit_nr and edit_nr > 0 and edit_nr <= #trader_goods ) then
			table.remove( trader_goods, edit_nr );
			self.trader_goods       = trader_goods;
			minetest.chat_send_player( pname, 'Deleted. This trade is no longer offered.');
		end
		-- display all offers (minus the deleted one)
		menu_path[2] = nil;
	end


	-- the player wants to store a new trade offer or change an existing one
	if( menu_path and #menu_path > 1 and (menu_path[2]=='storenew' or menu_path[2]=='storechange')) then

		local error_msg = '';
		local offer     = {};
		-- t1 has to be filled in - it has to contain the stack the player wants to offer
		if( not( fields[ 't1' ] ) or fields[ 't1'] == '' ) then
			error_msg = 'Error: What do you want to offer? Please enter something after \'Sell:\'!';
		end
		for i=1,mobf_trader.MAX_ALTERNATE_PAYMENTS do
			local text = fields[ 't'..tostring(i) ];
			if( text and text ~= '' ) then
				local help = text:split( ' ' );
				-- if no amount is given, assume 1
				if( #help < 2 ) then
					help[2] = 1;
				end
				-- the amount of items can only be positive
				help[2] = tonumber( help[2] );
				if( not( help[2] ) or help[2]<1 ) then
					error_msg = 'Error: Negative amounts are not supported: \''..( text )..'\'.';
				end
				-- money and money2 are acceptable as well
				if( not( minetest.registered_items[ help[1] ] ) and help[1]~='mobf_trader:money' and help[1]~='mobf_trader:money2') then
					error_msg = 'Error: \''..tostring( help[1] )..'\' is not a valid item. Please check your spelling.';
				end
				if( error_msg == '' ) then
					table.insert( offer, text );
				end
			end
		end
		if( #offer < 2 ) then
			error_msg = 'Please provide at least one form of payment.';
		end
		if( #trader_goods >= mobf_trader.MAX_OFFERS and menu_path[2]=='storenew') then
			error_msg = 'Sorry. Each trader can only make up to '..tostring( mobf_trader.MAX_OFFERS )..' diffrent offers.';
		end


		if(     error_msg == '' and menu_path[2]=='storenew') then
			if( not(trader_goods )) then
				trader_goods = {};
			end
			-- TODO: check if a similar offer exists already
			table.insert( trader_goods, offer ); 
			-- inform the trader about his new offer
			self.trader_goods = trader_goods;
			
			-- display the newly stored offer
			minetest.chat_send_player( pname, 'Your new offer has been added.');

			-- make sure the new offer is selected and displayed when this function here continues
			menu_path[2] = #trader_goods;

		elseif( error_msg == '' and menu_path[2]=='storechange') then
			if( not(trader_goods )) then
				trader_goods = {};
			end
			local edit_nr = tonumber( menu_path[3] );
			-- store the modified offer
			if( edit_nr and edit_nr > 0 and edit_nr <= #trader_goods ) then
				trader_goods[ edit_nr ] = offer;
				self.trader_goods       = trader_goods;
				minetest.chat_send_player( pname, 'The offer has been changed.');
			end
			-- display the modified offer
			menu_path[2] = edit_nr;
			menu_path[3] = nil;

		-- in case of error: display the input again so that the player can edit it
		elseif( menu_path[2]=='storenew' ) then
			menu_path[2] = 'add';
			formspec = formspec..
				'textarea[1.0,0.5;9,1.5;info;;'..minetest.formspec_escape( error_msg  )..']';
					
		-- changing an existing offer failed; offer to edit it
		elseif( menu_path[2]=='storechange' ) then
			menu_path[2] = 'change';
			formspec = formspec..
				'textarea[1.0,0.5;9,1.5;info;;'..minetest.formspec_escape( error_msg  )..']';
		end
	end


	-- add a new trade offer for the individual trader
	if( menu_path and #menu_path > 1 and (menu_path[2]=='add' or menu_path[2]=='edit')) then

		local player_inv = player:get_inventory();
		local edit_nr    = 0;

		if(     menu_path[2]=='add' ) then
			formspec = formspec..
				'button[0.5,6.3;2,0.5;'..npc_id..'_storenew;Store]'..
				'button[3.0,6.3;2,0.5;quit;Abort]'..
				'label[3.0,0.5;Add a new trade offer]'..
				'textarea[1.0,1.5;9,1.5;info;;'..( minetest.formspec_escape( 
					'Plese enter what you want to trade in exchange for what.\n'..
					'The items in the top row of your inventory serve as sample entries to the fields here.\n'..
					'Please edit the input fields to suit your needs or abort and re-arrange your inventory so\n'..
					'that what you want to offer is leftmost, while trade goods you ask for extend to the right.'))..']';
		elseif( menu_path[2]=='edit' ) then
			formspec = formspec..
				'button_exit[0.5,6.3;2,0.5;'..npc_id..'_storechange_'..menu_path[3]..';Store]'..
				'button_exit[3.0,6.3;2,0.5;quit;Abort]'..
				'label[3.0,0.5;Edit trade offer]'..
				'textarea[1.0,1.5;9,1.5;info;;'..minetest.formspec_escape( 
					'Plese edit this trade offer according to your needs.')..']';
			edit_nr = tonumber( menu_path[3] );
			if( not( edit_nr ) or edit_nr < 1 or edit_nr>#trader_goods ) then
				edit_nr = 0;
			end
		end

		for i=1,mobf_trader.MAX_ALTERNATE_PAYMENTS do
			local text  = '';
			local stack = player_inv:get_stack( 'main', i );
			local o     = 0;
			local ltext = 'or';
			-- edit input from previous attempt
			if( fields and fields[ 't'..tostring(i) ] ) then
				text = fields[ 't'..tostring(i) ];
			-- edit an existing offer
			elseif( edit_nr and edit_nr > 0 and edit_nr <= #trader_goods ) then
				text = ( trader_goods[ edit_nr ][i] or '');
			-- take what's in the player's inventory as a base
			elseif( not( stack:is_empty() )) then
				text = stack:get_name()..' '..stack:get_count();
			else
				text = '';
			end
			-- the 'Sell' is not as far to the right as the rest
			if(     i==1 ) then
				o     = -1;
				ltext = 'Sell';
			elseif( i==2 ) then
				ltext = 'for';
			end
			formspec = formspec..
				'label['..(2.0+o)..','..( 2.5+(i*0.5))..';'..ltext..']'..
				'field['..(3.1+o)..','..( 2.7+(i*0.5))..';7,1.0;t'..tostring(i)..';;'..
					minetest.formspec_escape( text )..']';
		end
				
		minetest.show_formspec( pname, "mobf_trader:trader", formspec );
		return;
	end



	if( menu_path and #menu_path > 0 ) then
		formspec = formspec..
			 'button[4.5,6.3;2,0.5;'..menu_path[1]..';Show goods]';
	end


	-- it is possible to display up to 4 items which may together form one offer; this needs a diffrent sort of visualization
	local offer_packages = false;
	for j,k in ipairs( trader_goods ) do
		for i,v in ipairs( k ) do
			if( not( offer_packages ) and type( v )=='table' ) then
				offer_packages = true;
			end
		end
	end

	-- move some entries up in order to have enough space
	local m_up = 0;
	local p_up = 0;
	if( not( menu_path ) or #menu_path == 1 ) then
		m_up =  1.0;
	elseif(  menu_path  and #menu_path == 2 ) then
		-- displaying a package with up to 4 items takes more space
		if( offer_packages ) then
			m_up =  0.0;
			p_up =  0.5; 
		else
			m_up =  0.5;
			p_up =  1.0; 
		end
	elseif(  menu_path  and #menu_path > 2 ) then
		if( offer_packages ) then
			m_up =  -1.0;
			p_up =  -1.0; 
		else
			m_up =   0.0; 
			p_up =   0.0; 
		end
	end

	-- intorduce the trader
	local greeting1 = 'My name is '..tostring( self.trader_name )..'.';
	local greeting2 = 'I sell the following:';

	local greeting3 = '';
	if( self.trader_owner and self.trader_owner ~= '' ) then
		greeting3 = tostring( self.trader_owner )..' is my employer.';
	else
		greeting3 = 'I work for myshelf.';
	end

	formspec = formspec..'label[0.5,'..(0.5+m_up)..';'..minetest.formspec_escape( greeting1 )..']'..
		             'label[3.5,'..(0.5+m_up)..';'..minetest.formspec_escape( greeting2 )..']'..
		             'label[6.5,'..(0.5+m_up)..';'..minetest.formspec_escape( greeting3 )..']'..
		             'label[0.2,'..(1.5+m_up)..';Goods:]';



	-- the owner and people with the trader_take priv can pick the trader up
	-- (he will end up in the inventory and can then be placed elsewhere)
	if( (self.trader_owner and self.trader_owner == pname)
	  or minetest.check_player_privs( pname, {trader_take=true})) then

		formspec = formspec..'button[9,0.5;1,0.5;'..npc_id..'_take;Take]';
	end

	
	-- only the owner can add offers
	if( (self.trader_owner and self.trader_owner == pname ) and self.trader_typ=='individual') then
		formspec = formspec..'button[9,'..(1.5+m_up)..';1,0.5;'..npc_id..'_add;Add]'; 
	end


	-- show the goods the trader has to offer
	for i,v in ipairs( trader_goods ) do

		formspec = formspec..mobf_trader.show_trader_formspec_item_list(
				((i-1)%8)+1, math.floor((i-1)/8)*1.2+(1.0+m_up), v[1], i, npc_id, 0.4, 0.4, 0.6);
	end


	-- give information about a specific good
	if( menu_path and #menu_path >= 2 ) then

		local choice1 = tonumber( menu_path[2] );

		-- in case the client sends invalid input
		if( not( choice1 ) or choice1 > #trader_goods ) then
			choice1 = 1;
		end

		local trade_details = trader_goods[ choice1 ];


		if( #menu_path >= 2 ) then

			-- if that button is clicked, show the same formspec again
			if( offer_packages ) then 
				formspec = formspec..
					'label[0.3,'..(5.1+p_up)..';Get all of this]'..
					'label[2.0,'..(4.1+p_up)..';for]'..
					'label[3.0,'..(3.00+p_up)..';Select what you want to give:]'..

					mobf_trader.show_trader_formspec_item_list(
						0, 4.0+p_up-0.6, trade_details[1], menu_path[2], npc_id, 1.0, 1.0, 1 )..
						'box[-0.15,'..(4.0+p_up-0.70)..';2.1,2.4;#00AA00]';
			else
				formspec = formspec..
					'label[0.3,'..(4.0+p_up)..';Get]'..

					mobf_trader.show_trader_formspec_item_list(
						0.5, 4.0+p_up-0.6, trade_details[1], menu_path[2], npc_id, 1.0, 1.0, 1 );
			end


			if( (self.trader_owner and self.trader_owner == pname ) and self.trader_typ=='individual') then
				formspec = formspec..'button[9,'..(3.7+p_up)..';1,0.5;'..npc_id..'_delete_'..menu_path[2]..';Delete]'..
				                     'button[9,'..(4.7+p_up)..';1,0.5;'..npc_id..'_edit_'..  menu_path[2]..';Edit]'; 
			end

			-- the real options here are the prices
			npc_id   = npc_id..'_'..menu_path[2];

			local or_or_for = 'for';
			for i,v in ipairs( trade_details ) do
	
				-- the first entry is the good that is offered; all subsequent ones are prices
				if( i > 1 ) then
					if( i > 2 ) then
						or_or_for = 'or';
					end
					if( offer_packages ) then 
						formspec = formspec..
							'label['..((i-1)*2.40+0.0)..','..(5.1+p_up)..';'..or_or_for..']'..
							'button['..((i-1)*2.40+0.3)..','..(5.3+p_up)..';1.5,0.5;'..
							 npc_id..'_'..tostring( i )..';Payment '..tostring(i-1)..']'..

							mobf_trader.show_trader_formspec_item_list(
								((i-1)*2.40), 4.0+p_up-0.6, trade_details[i], i, npc_id, 1.0, 1.0, 1 )..
								'box['..(-0.15+((i-1)*2.40))..','..(4.0+p_up-0.70)..';2.1,2.4;#0000CC]';
					else
						formspec = formspec..
							'label['..((i)*1.2-0.3)..','..(4.0+p_up)..';'..or_or_for..']'..
							mobf_trader.show_trader_formspec_item_list(
								((i)*1.2-0.5), 4.0+p_up-0.6, trade_details[i], i, npc_id, 1.0, 1.0, 1 );
					end
				end
			end
		end

		if( #menu_path >= 3 ) then

			local res = mobf_trader.do_trade( self, player, menu_path, trade_details );

			if( res.msg ) then
				formspec = formspec..
					'textarea[1.0,5.1;8,1.0;info;;'..( minetest.formspec_escape( res.msg ))..']';
			end
			if( res.success ) then
				formspec = formspec..
					'button[1.0,5.8;2.5,0.5;'..menu_path[1]..'_'..menu_path[2]..'_'..menu_path[3]..';Repeat the trade]';
			end
			formspec = formspec..'button[1.5,6.3;2,0.5;'..menu_path[1]..'_'..menu_path[2]..';Show prices]';
		end	
		
		-- show the amount of sold items after the purchase
		if( menu_path and #menu_path >= 2 ) then
			-- show how much of these items/packages have been sold already
			if(    self.trader_sold
			   and self.trader_sold[ trade_details[ 1 ]]) then
				formspec = formspec..'label[9.0,'..(4.0+p_up)..';Sold: '..
					tostring( self.trader_sold[ trade_details[ 1 ]] )..']';
			else
				formspec = formspec..'label[9.0,'..(4.0+p_up)..';Sold: -';
			end
		end
	end

	minetest.show_formspec( pname, "mobf_trader:trader", formspec );
end




-- checks if the deptor can pay the price to the receiver (and if the receiver can take it)
-- if the other side is an admin shop/trader with unlimited supply:
--          receiver_name has to be nil or '' and  receiver_inv has to be empty for unlmiited trade
mobf_trader.can_trade = function( price_stack_str, debtor_name, debtor_inv, receiver_name, receiver_inv, player_is_debtor )

	price_stack = ItemStack( price_stack_str );
	-- get information about the price
	local price_desc        = '';
	local price_stack_name  = price_stack:get_name();
	local price_stack_count = price_stack:get_count();
	-- this is set to a text message in case something can't be paid
	local error_msg         = '';
	-- the trade may contain money (from two diffrent mods) or items; this indicates which tpye was choosen by price_stack_str
	local price_type        = '?';
	-- empty price stacks are pointless for a trader
	if(     price_stack:is_empty() or price_stack_count < 0) then
		error_msg  = 'Sorry. This is no exchange of presents. Both sides have to contribute to the trade. The following is not acceptable: '..
				tostring( price_stack_str );
		price_desc = price_stack_str;

	-- in case the money mod is used
	elseif( price_stack_name == 'mobf_trader:money') then
		price_type = 'money';
		price_desc = CURRENCY_PREFIX..price_stack_count..CURRENCY_POSTFIX;

		if( not( money ) or not( money.exist )) then
			error_msg = 'Sorry. There seems to be something wrong with the money mod.';

		elseif( debtor_name   and debtor_name   ~= '' and not( money.exist( debtor_name ))) then
			error_msg = 'no_account_debtor';

		-- the other party needs an account as well (except for admin shops)
		elseif( receiver_name and receiver_name ~= '' and not( money.exist( receiver_name ))) then
			error_msg = 'no_account_receiver';

		elseif( debtor_name and money.get_money( debtor_name ) < price_stack_count ) then
			error_msg = 'no_money';
		end

	-- in case the money2 mod is used
	elseif( price_stack_name == 'mobf_trader:money2') then
		price_type = 'money2';
		price_desc = price_stack_count..' '..( money.currency_name or 'cr' );

		if( not( money ) or not( money.has_credit ) or not( money.get )) then
			error_msg = 'Sorry. There seems to be something wrong with the money2 mod.';

		elseif( debtor_name   and debtor_name   ~= '' and not( money.has_credit( debtor_name ))) then
			error_msg = 'no_account_debtor';

		elseif( receiver_name and receiver_name ~= '' and not( money.has_credit( receiver_name ))) then
			error_msg = 'no_account_receiver';

		elseif( debtor_name and money.get( debtor_name ) < price_stack_count ) then
			error_msg = 'no_money';
		end


	-- item-based trade 
	else
		price_type = 'direct';
		if( not( minetest.registered_items[ price_stack_name ] )) then

			error_msg  = 'There is something wrong with my offer. Seems \''..tostring( price_stack_name )..'\' does not exist anymore.';
			price_desc = price_stack_name;

		else
			price_desc = price_stack_count..'x '..
				( minetest.registered_items[ price_stack_name ].description or price_stack_name);
		end	

		-- does the debtor have the item? 
		if(       debtor_inv and not( debtor_inv:contains_item("main", price_stack ))) then
			error_msg = 'no_item';
		-- does the receiver have enough free room to take the item?
		elseif( receiver_inv and not( receiver_inv:room_for_item("main", price_stack ))) then
			error_msg = 'no_space';
		end
	end


	if( error_msg == '' ) then
		return { error_msg = nil, price_desc = price_desc, price_stack = price_stack, price_type = price_type };
	end

	-- create extensive error messages, depending on who does lack what in order to finish the trade
	if(     error_msg == 'no_account_debtor' ) then
		if( player_is_debtor ) then
			error_msg = 'You do not have a bank account. Please get one so that we can trade.';
		else
			error_msg = 'Sorry. I lost my bank account data. Please contact my owner!';
		end

	elseif( error_msg == 'no_account_receiver') then
		if( not(player_is_debtor)) then
			error_msg = 'You do not have a bank account. Please get one so that we can trade.';
		else
			error_msg = 'Sorry. I lost my bank account data. Please contact my owner!';
		end

	elseif( error_msg == 'no_money' ) then
		if( player_is_debtor) then
			error_msg = 'You do not have enough money. The price is '..tostring( price_desc )..'.';
		else
			error_msg = 'Sorry, my shop ran out of money. I cannot afford to buy. Please come back later!';
		end

	elseif( error_msg == 'no_item' ) then
		if( player_is_debtor) then
			error_msg = 'You do not have '..tostring( price_desc )..'.';
		else
			error_msg = 'Oh. I just noticed that I ran out of '..tostring( price_desc )..'. Please come back later!';
		end

	
	elseif( error_msg == 'no_space' ) then
		if( player_is_debtor) then
			error_msg = 'Sorry. I do not have any storage space left for '..tostring( price_desc )..'. Please come back later!';
		else
			error_msg = 'You do not have enough free space in your inventory for '..tostring( price_desc )..'.';
		end
	end


	-- price_desc is important for printing out the price to the player
	return { error_msg = error_msg, price_desc = price_desc, price_stack = price_stack, price_type = price_type };
end




-- check if payment and trade are possible; do the actual trade
-- self ought to contain: trader_id, trader_typ, trader_owner, trader_home_pos, trader_sold (optional - for statistics)
mobf_trader.do_trade = function( self, player, menu_path, trade_details )

	if( not( self ) or not( player ) or not( menu_path ) or #menu_path < 3) then
		return {msg='', success=false};
	end

	local player_inv = player:get_inventory();
	local pname      = player:get_player_name();
	local choice2    = tonumber( menu_path[3] );
	local formspec   = '';

	-- the first entry is what is sold
	if( not( choice2 ) or choice2 > #trade_details or choice2 < 2) then
		choice2 = 2;
	end

	local trader_inv   = nil; 
	-- traders who do have an owner need to have an inventory somewhere
	if( self.trader_owner and self.trader_owner ~= '' and self.trader_typ=='individual') then

		if( not( self.trader_home_pos ) ) then
			self.trader_home_pos = {x=0,y=0,z=0};
		end

		local node = minetest.get_node( self.trader_home_pos );
		local meta = minetest.get_meta( self.trader_home_pos );

		-- the object at trader_home_pos has to be owned by the trader owner (hopefully it's a chest!
		if( node and meta and meta:get_string('owner') and meta:get_string('owner')==self.trader_owner ) then
	
			trader_inv = meta:get_inventory();
		end

		if( not( trader_inv ) or trader_inv:is_empty()) then
			return {msg='Sorry. I was unable to find my storage chest. Please contact my owner!', success=false};
		end
	end

	-- can the player pay the selected payment to the trader?
	local player_can_trade = mobf_trader.can_trade( trade_details[ choice2 ], pname, player_inv, self.trader_owner, trader_inv, true );
	if( player_can_trade.error_msg ) then
		return {msg=player_can_trade.error_msg, success=false};
	end

	-- can the trader in turn give the player what the player paid for?
	local trader_can_trade = mobf_trader.can_trade( trade_details[ 1       ], self.trader_owner, trader_inv, pname, player_inv, false );
	if( trader_can_trade.error_msg ) then
		return {msg=trader_can_trade.error_msg, success=false};
	end
		

	-- both sides are able to give what they agreed on - the trade may progress;
	-- traders that use money/money2 need to have an owner for their account

	-- the player pays first
	if(     player_can_trade.price_type == 'money' ) then
		local amount = player_can_trade.price_stack:get_count();
		money.set_money( self.trader_owner, get_money( self.trader_owner ) + amount );
		money.set_money( pname,             get_money( pname )             - amount );
				
	elseif( player_can_trade.price_type == 'money2' ) then
		local res = money.transfer( pname, self.trader_owner, player_can_trade.price_stack:get_count() );
		if( res ) then
			return {msg='Internal error: Payment failed: '..tostring( res )..'.', success=false};
		end

	elseif( player_can_trade.price_type == 'direct' ) then
		player_inv:remove_item(     "main", trade_details[ choice2 ] );
		if( trader_inv ) then
			trader_inv:add_item("main", trade_details[ choice2 ] );
		end
	end


	-- the trader replies
	if(     trader_can_trade.price_type == 'money' ) then
		local amount = trader_can_trade.price_stack:get_count();
		money.set_money( pname,             get_money( pname )             + amount );
		money.set_money( self.trader_owner, get_money( self.trader_owner ) - amount );
				
	elseif( trader_can_trade.price_type == 'money2' ) then
		local res = money.transfer( self.trader_owner, pname, trader_can_trade.price_stack:get_count() );
		if( not( res )) then
			return {msg='Internal error: Payment failed.', success=false};
		end

	elseif( trader_can_trade.price_type == 'direct' ) then
		player_inv:add_item(           "main", trade_details[ 1 ] );
		if( trader_inv ) then
			trader_inv:remove_item("main", trade_details[ 1 ] );
		end
	end


	-- let the trader do some statistics
	if( not( self.trader_sold )) then
		self.trader_sold = {};
	end
	if( not( self.trader_sold[ trade_details[ 1 ]] )) then
		self.trader_sold[  trade_details[ 1 ]] = 1;
	else
		self.trader_sold[  trade_details[ 1 ]] = self.trader_sold[ trade_details[ 1 ]] +1;
	end

	-- log the action
	mobf_trader.log( player:get_player_name()..
		' gets '..tostring( trade_details[ 1 ])..
		' for ' ..tostring( trade_details[ choice2 ])..
		' from '..tostring( self.trader_id )..
		' (owned by '..tostring( self.trader_owner )..')');


	return {msg='You got '..trader_can_trade.price_desc..' for your '..player_can_trade.price_desc..
			'.\nThank you! Would you like to trade more?', success=true};
end




-- pick the trader up and store in the players inventory;
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


-- formspec input received
mobf_trader.form_input_handler = function( player, formname, fields)

	-- are we responsible to handle this input?
	if( not( formname ) or formname ~= "mobf_trader:trader" ) then
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
				else
					mobf_trader.show_trader_formspec( trader, player, menu_path, fields );
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



-- initialize a newly created trader
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
			mobf_trader.show_trader_formspec( self, puncher, nil, nil );
		end
	end,


	-- show the trade menu
	on_rightclick = function(self, clicker)

		if( not( self) or not( clicker )) then
			return;
		end

		mobf_trader.show_trader_formspec( self, clicker, nil, nil );
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
		self.trader_goods     = {},
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