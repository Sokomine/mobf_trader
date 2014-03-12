
----------------------------------------------------------------------------
--  The only relevant function for other mods to call here is:
--      mob_trading.show_trader_formspec( self, player, menu_path, fields )
--  All other functions are more or less internal.
--  Calls the following functions in the mobf_trader namespace:
--      mobf_trader.get_face_direction(..)    
--      mobf_trader.log(..)
----------------------------------------------------------------------------


-- contains mostly defines and functions
mob_trading = {};

mob_trading.MAX_OFFERS                = 24; -- up to that many diffrent offers are supported by the trader of the type 'individual'
mob_trading.MAX_ALTERNATE_PAYMENTS    = 6; -- up to 6 diffrent payments are possible for each good offered

-- how many nodes does the trader of the type individual search for locked chests?
mob_trading.LOCKED_CHEST_SEARCH_RANGE = 3;

-- pseudo-item so that something can be entered when money from the money mod (which does not exist as an item) is requested
mob_trading.MONEY_ITEM   = 'money';
-- same for the money2 mod
mob_trading.MONEY2_ITEM  = 'money2';





-------------------------------------------------------------------------------
-- main formspec of the trader
-------------------------------------------------------------------------------
-- the trader entity turns towards the player
-- usually shows the goods the trader has to offer plus trade details once an offer has been selected
--
-- self HAS to contain:
--      self.trader_id        unique id of the trader (unique for the entire map)
--      self.trader_name      i.e. 'Fritz'; used only for the greeting
--      self.object           trader mobs will turn toward the player; traders of the type individual need to find locked chests in their environment
--      self.trader_typ       needs to be an index of mobf_trader.npc_trader_data; required in order find out what the trader deals with (trader_goodsa)
--      self.trader_goods     required for traders of the typ individual; else determined through self.trader_typ
--      self.trader_owner     required for traders of the typ individual
--      self.trader_sold      used for collecting statistics
mob_trading.show_trader_formspec = function( self, player, menu_path, fields )

	if( not( self ) or not( player )) then
		return;
	end

	local pname = player:get_player_name();

	local npc_id = self.trader_id;
	if( not( npc_id )) then
		return;
	end

	-- turn towards the customer
	if( self.object and self.object.setyaw ) then
		self.object:setyaw( mobf_trader.get_face_direction( self.object:getpos(), player:getpos() ));
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
	-- for new trade offers; for this purpose, colored boxes are drawn around the relevant inventory slots
	if( (self.trader_owner and self.trader_owner == pname ) and self.trader_typ=='individual') then
		formspec = formspec..
			'label[-0.25,6.90;When adding]'..
			'label[-0.25,7.10;a new offer,]'..
			'label[-0.25,7.30;suggest this:]'..
			'label[1.1,6.5;Sell:]'..
					'box[0.95,6.7;0.95,4.35;#00AA00]'..
			'label[2.1,6.5;for:]'..
					'box[1.95,6.7;0.95,4.35;#0000CC]'..
			-- the Add button is also shown next to the player's inventory that provides the names
			'button[9,7.1;1,0.5;'..npc_id..'_add;Add]'..
			'button[1.1,10.9;3.9,0.5;'..npc_id..'_addm;Add offer based on these colored slots]';
		for i = 3, mob_trading.MAX_ALTERNATE_PAYMENTS do
			local boxcolor = '#0000CC';
			formspec = formspec..'label['..(tostring(i)+0.1)..',6.5;or:]';
			-- complex offers of up to 4 items allow only 3 alternate payments
			if( i<=4 ) then
				boxcolor = '#0000CC';
				if(( i%2 )==1 ) then
					boxcolor = '#AAAAAA';
				end
				formspec = formspec..'box['..( i-0.05 )..',6.7;0.95,4.35;'..boxcolor..']';
			else
				boxcolor = '#000077';
				if(( i%2 )==1 ) then
					boxcolor = '#777777';
				end
				formspec = formspec..'box['..( i-0.05 )..',6.7;0.95,1.25;'..boxcolor..']';
			end
		end
	end


	-- back to main menu (player clicked 'Abort' in the add/edit new offer menu)
	if( menu_path and #menu_path > 1 and menu_path[2]=='main') then
		menu_path[2] = nil;
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
	if( menu_path and #menu_path > 1 and (menu_path[2]=='storenew' or menu_path[2]=='storenewm' or menu_path[2]=='storechange')) then

		local error_msg = mob_trading.store_trade_offer_changes( self, pname,  menu_path, fields, trader_goods );

		-- in case of error: display the input again so that the player can edit it
		if( error_msg ~= '' ) then
			if(     menu_path[2]=='storenewm') then 
				menu_path[2] = 'addm';
			elseif( menu_path[2]=='storenew' ) then
				menu_path[2] = 'add';
			elseif( menu_path[2]=='storechange' ) then
				menu_path[2] = 'edit';
			end
			-- show the error
			formspec = formspec..
				'textarea[1.0,1.6;9,0.5;info;;'..minetest.formspec_escape( error_msg  )..']';
			-- send the player a chat message as well
			minetest.chat_send_player( pname, error_msg );
		end
	end


	-- add a new trade offer for the individual trader
	if( menu_path and #menu_path > 1 and (menu_path[2]=='add' or menu_path[2]=='edit' or menu_path[2]=='addm')) then

		mob_trading.show_trader_formspec_edit( self, player,  menu_path, fields, trader_goods, formspec, npc_id, pname );
		-- the function above already displayed a formspec; nothing more to do here
		return;
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
	local greeting1 = 'My name is '..tostring( self.trader_name or 'uniportant')..'.';
	local greeting2 = 'I sell the following:';

	local greeting3 = '';
	if( self.trader_owner and self.trader_owner ~= '' ) then
		if( self.trader_owner == pname ) then
			greeting3 = 'You are my employer.';
		else
			greeting3 = tostring( self.trader_owner )..' is my employer.';
		end
	else
		greeting3 = 'I work for myshelf.';
	end

	if( menu_path and menu_path[1] ) then
	      formspec = formspec..'button[4.5,6.3;2,0.5;'..menu_path[1]..';Show goods]';
	end

	formspec = formspec..'label[0.5,'..(0.5+m_up)..';'..minetest.formspec_escape( greeting1 )..']'..
		             'label[3.5,'..(0.5+m_up)..';'..minetest.formspec_escape( greeting2 )..']'..
		             'label[6.5,'..(0.5+m_up)..';'..minetest.formspec_escape( greeting3 )..']'..
		             'label[0.2,'..(1.5+m_up)..';Goods:]';



	-- the owner and people with the trader_take priv can pick the trader up
	-- (he will end up in the inventory and can then be placed elsewhere)
	if( (self.trader_owner and self.trader_owner == pname)
	  or minetest.check_player_privs( pname, {trader_take=true})) then

		formspec = formspec..'button_exit[9,0.5;1,0.5;'..npc_id..'_take;Take]';
	end

	
	-- show the goods the trader has to offer
	for i,v in ipairs( trader_goods ) do

		formspec = formspec..mob_trading.show_trader_formspec_item_list(
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

		-- when offering 6 diffrent methods of payment, we can't display 4 items per payment - there's simply not enough space
		if( offer_packages and #trade_details > 4 ) then
			offer_packages = false;
		end

		if( #menu_path >= 2 ) then

			-- if that button is clicked, show the same formspec again
			if( offer_packages ) then 
				formspec = formspec..
					'label[0.3,'..(5.1+p_up)..';Get all of this]'..
					'label[2.0,'..(4.1+p_up)..';for]'..
					'label[3.0,'..(3.00+p_up)..';Select what you want to give:]'..

					mob_trading.show_trader_formspec_item_list(
						0, 4.0+p_up-0.6, trade_details[1], menu_path[2], npc_id, 1.0, 1.0, 1 )..
						'box[-0.15,'..(4.0+p_up-0.70)..';2.1,2.4;#00AA00]';
			else
				formspec = formspec..
					'label[0.3,'..(4.0+p_up)..';Get]'..
					'box[0.25,'..(3.8+p_up)..';1.75,1.10;#00AA00]'..

					mob_trading.show_trader_formspec_item_list(
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
	
				local boxcolor = '#0000CC';
				-- the first entry is the good that is offered; all subsequent ones are prices
				if( i > 1 ) then
					if( i > 2 ) then
						or_or_for = 'or';
					end
					if( i%2==1 ) then
						boxcolor = '#AAAAAA';
					end
					if( offer_packages ) then 
						formspec = formspec..
							'label['..((i-1)*2.40+0.0)..','..(5.1+p_up)..';'..or_or_for..']'..
							'button['..((i-1)*2.40+0.3)..','..(5.3+p_up)..';1.5,0.5;'..
							 npc_id..'_'..tostring( i )..';Payment '..tostring(i-1)..']'..

							mob_trading.show_trader_formspec_item_list(
								((i-1)*2.40), 4.0+p_up-0.6, trade_details[i], i, npc_id, 1.0, 1.0, 1 )..
								'box['..(-0.15+((i-1)*2.40))..','..(4.0+p_up-0.70)..';2.1,2.4;'..boxcolor..']';
					else
						formspec = formspec..
							'label['..((i)*1.2-0.3)..','..(4.0+p_up)..';'..or_or_for..']'..
							'box['..((i*1.2)-0.34)..','..(3.8+p_up)..';1.15,1.10;'..boxcolor..']'..
							mob_trading.show_trader_formspec_item_list(
								((i*1.2)-0.5), 4.0+p_up-0.6, trade_details[i], i, npc_id, 1.0, 1.0, 1 );
					end
				end
			end
		end

		if( #menu_path >= 3 ) then

			local res = mob_trading.do_trade( self, player, menu_path, trade_details );

			if( res.msg ) then
				formspec = formspec..
					'textarea[1.0,5.1;8,1.0;info;;'..( minetest.formspec_escape( res.msg ))..']';
				minetest.chat_send_player( pname, res.msg );
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

	minetest.show_formspec( pname, "mob_trading:trader", formspec );
end




-- helper function
mob_trading.show_trader_formspec_item = function( offset_x, offset_y, stack_desc, nr, prefix, size )

	local stack = ItemStack( stack_desc );
	local anz   = stack:get_count();
	local name  = stack:get_name();
	local label = '';
	-- show the label with the amount of item showed only if more than one is sold and the button is large enough
	if( anz > 1 and size>0.7) then
		label = 'label['..(offset_x+0.5*size)..','..(offset_y+0.4*size)..';'..tostring( anz )..'x]';
	else
		label = '';
	end
	
	-- do not show unknown blocks
	if( minetest.registered_items[ name ] ) then

		if( name==mob_trading.MONEY_ITEM or name==mob_trading.MONEY2_ITEM) then
			return 'image_button['..offset_x..','..offset_y..';'..size..','..size..';'..
-- TODO: create placeholder texture for money: mobf_trader_money.png
				'mobf_trader_money.png;false;true]'..
				label;
		else
			return	'item_image_button['..offset_x..','..offset_y..';'..size..','..size..';'..
				( name or '?')..';'..
				prefix..'_'..tostring( nr )..';]'..
				label;
--			return	'item_image['..offset_x..','..offset_y..';'..size..','..size..';'..
--				( name or '?')..']'..
--				label;
		end
	end
	return '';
end


-- shows up to four items
-- set stretch_x and stretch_y to 0.4 each plus quarter_botton_size to 0.6 in order to make everything fit into one formspec
mob_trading.show_trader_formspec_item_list = function( offset_x, offset_y, stack_desc, nr, prefix, stretch_x, stretch_y, quarter_button_size )

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
				mob_trading.show_trader_formspec_item(offset_x+(a*stretch_x), offset_y+(b*stretch_y), stack_desc[i], nr, prefix, quarter_button_size );

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

		return mob_trading.show_trader_formspec_item( offset_x, offset_y, stack_desc, nr, prefix, 1 );
	end
end



-- this is only relevant for the trader of the typ "individual"
-- (that trader uses player-owned chests to store the trade goods)
mob_trading.show_storage_formspec = function( self, player, menu_path )

	local pos = self.object:getpos();
	local RANGE = mob_trading.LOCKED_CHEST_SEARCH_RANGE;

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




--------------------------------------------------
-- Store new trade offer or change existing one
--------------------------------------------------
-- changes trader_goods if the add or edit succeeded
-- changes menu_path so that the newly added/edited offer is displayed
-- sends a chat message to the player in case of success and returns ''; else returns error message
mob_trading.store_trade_offer_changes = function( self, pname,  menu_path, fields, trader_goods )

	local offer = {};
	local i = 1;
	local j = 1;

	-- t1 has to be filled in - it has to contain the stack the player wants to offer
	if(   (not( fields[ 't1' ] ) or fields[ 't1'] == '' )
	  and (not( fields[ 't2' ] ) or fields[ 't2'] == '' )
	  and (not( fields[ 't3' ] ) or fields[ 't3'] == '' )
	  and (not( fields[ 't4' ] ) or fields[ 't4'] == '' )) then
		return 'Error: What do you want to offer? Please enter something after \'Sell:\'!';
	end

	for i=1,mob_trading.MAX_ALTERNATE_PAYMENTS do
		local offer_one_side = {};
		for j=1,4 do
			local text = fields[ 't'..tostring(((i-1)*4)+j) ];
			if( text and text ~= '' ) then
				local help = text:split( ' ' );
				-- if no amount is given, assume 1
				if( #help < 2 ) then
					help[2] = 1;
				end
				-- the amount of items can only be positive
				help[2] = tonumber( help[2] );
				if( not( help[2] ) or help[2]<1 ) then
					return 'Error: Negative amounts are not supported: \''..( text )..'\'.';
				end
				-- money and money2 are acceptable as well
				if( not( minetest.registered_items[ help[1] ] ) and help[1]~=mob_trading.MONEY_ITEM and help[1]~=mob_trading.MONEY2_ITEM) then
					return 'Error: \''..tostring( help[1] )..'\' is not a valid item. Please check your spelling.';
				end
				table.insert( offer_one_side, text );
			end
		end
		-- use a string to store
		if( #offer_one_side==1) then
			table.insert( offer, offer_one_side[1] );
		-- use a table to store (necessary when up to four items are bundled)
		elseif( #offer_one_side>1) then
			table.insert( offer, offer_one_side );
		end
	end
	if( #offer < 2 ) then
		return 'Please provide at least one form of payment.';
	end
	if( #trader_goods >= mob_trading.MAX_OFFERS and (menu_path[2]=='storenew' or menu_path[2]=='storenewm')) then
		return 'Sorry. Each trader can only make up to '..tostring( mob_trading.MAX_OFFERS )..' diffrent offers.';
	end


	if( not(trader_goods )) then
		trader_goods = {};
	end
	if( menu_path[2]=='storenew' or menu_path[2]=='storenewm') then
		-- TODO: check if a similar offer exists already
		table.insert( trader_goods, offer ); 
		-- inform the trader about his new offer
		self.trader_goods = trader_goods;
			
		-- display the newly stored offer
		minetest.chat_send_player( pname, 'Your new offer has been added.');

		-- make sure the new offer is selected and displayed when this function here continues
		menu_path[2] = #trader_goods;
		return '';

	elseif( menu_path[2]=='storechange') then
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
		return '';
	end
	return 'Error: Unknown command.';
end


-------------------------------------------------------------------------------
-- show a formspec that allows to add a new trade offer or edit an existing one
-------------------------------------------------------------------------------
mob_trading.show_trader_formspec_edit = function( self, player,  menu_path, fields, trader_goods, formspec, npc_id, pname )


	local player_inv = player:get_inventory();
	local edit_nr    = 0;

	if(     menu_path[2]=='add') then
		formspec = formspec..
			'button[0.5,6.3;2,0.5;'..npc_id..'_storenew;Store]'..
			'button[3.0,6.3;2,0.5;'..npc_id..'_main;Abort]'..
			'label[3.0,-0.2;Add a new simple trade offer]'..
			'textarea[1.0,0.5;9,1.5;info;;'..( minetest.formspec_escape( 
				'Plese enter what you want to trade in exchange for what.\n'..
				'The items in the top row of your inventory serve as sample entries to the fields here.\n'..
				'Please edit the input fields to suit your needs or abort and re-arrange your inventory so\n'..
				'that what you want to offer is leftmost, while trade goods you ask for extend to the right.'))..']';
	elseif( menu_path[2]=='addm' ) then
		formspec = formspec..
			'button[0.5,6.3;2,0.5;'..npc_id..'_storenewm;Store]'..
			'button[3.0,6.3;2,0.5;'..npc_id..'_main;Abort]'..
			'label[3.0,-0.2;Add a new complex trade offer]'..
			'textarea[1.0,0.5;9,1.5;info;;'..( minetest.formspec_escape( 
				'Plese enter which item(s) you want to trade in exchange for which item(s).\n'..
				'The items in the colored columns of your inventory serve as sample entries to the fields here.\n'..
				'Please edit the input fields to suit your needs or abort and re-arrange your inventory.\n'..
				'The green, blue and gray fields form bundles of up to four items.'))..']';
	elseif( menu_path[2]=='edit' ) then
		formspec = formspec..
			'button_exit[0.5,6.3;2,0.5;'..npc_id..'_storechange_'..menu_path[3]..';Store]'..
			'button_exit[3.0,6.3;2,0.5;'..npc_id..'_main;Abort]'..
			'label[3.0,-0.2;Edit trade offer]'..
			'textarea[1.0,1.5;9,0.5;info;;'..minetest.formspec_escape( 
				'Plese edit this trade offer according to your needs.')..']';
		edit_nr = tonumber( menu_path[3] );
		if( not( edit_nr ) or edit_nr < 1 or edit_nr>#trader_goods ) then
			edit_nr = 0;
		end
	end

	local texts = {};
	-- add a complex trade with multiple (up to four) items for each side? or is a 1:1 trade sufficient?
	local extended = false;
	if( menu_path[2]=='addm' ) then
		extended = true;
	end
	for i=1,mob_trading.MAX_ALTERNATE_PAYMENTS do
		for j=1,4 do
			local text  = '';

			-- edit input from previous attempt
			if( fields and fields[ 't'..tostring(((i-1)*4)+j) ] ) then
				text = fields[ 't'..tostring(((i-1)*4)+j) ];
			-- edit an existing offer
			elseif( edit_nr and edit_nr > 0 and edit_nr <= #trader_goods ) then
				if( type( trader_goods[ edit_nr ][i] )=='table' ) then
					text = ( trader_goods[ edit_nr ][i][j] or '');
					extended = true;
				elseif( j==1 ) then
					text = ( trader_goods[ edit_nr ][i]    or '');
				else
					text = '';
				end
			-- take what's in the player's inventory as a base
			else
				local stack = player_inv:get_stack( 'main', ((j-1)*8)+i );

				if( not( stack:is_empty() )) then
					text = stack:get_name()..' '..stack:get_count();
				else
					text = '';
				end
			end
			table.insert( texts, text );
		end
	end

	for i=1,mob_trading.MAX_ALTERNATE_PAYMENTS do
		local o     = 0;
		local ltext = 'or';
		local boxcolor = '#0000CC';
		-- the 'Sell' is not as far to the right as the rest
		if(     i==1 ) then
			o     = -1;
			ltext = 'Sell';
			boxcolor = '#00AA00';
		elseif( i==2 ) then
			ltext = 'for';
		elseif( i>1 and (i%2==1)) then
			boxcolor = '#AAAAAA';
		end
		if( extended ) then -- distinguish between simple (one item offered, 1 wanted) and complex (up to 4 offered; up to 4 wanted) trades
			if( i<5 ) then
			    formspec = formspec..
				'label['..(1.0+o)..','..( 1.0+(i*1.1))..';'..ltext..']'..
				'box['..(  0.8+o)..','..( 0.86+(i*1.1))..';9.1,1.04;'..boxcolor..']'..
				'field['..(2.1+o)..','..( 1.0+(i*1.1))..';3.9,1.0;t'..tostring((i*4)-3)..';;'..
					minetest.formspec_escape( texts[ (i*4)-3] )..']'..
				'field['..(2.1+o)..','..( 1.5+(i*1.1))..';3.9,1.0;t'..tostring((i*4)-2)..';;'..
					minetest.formspec_escape( texts[ (i*4)-2] )..']'..
				'field['..(6.2+o)..','..( 1.0+(i*1.1))..';3.9,1.0;t'..tostring((i*4)-1)..';;'..
					minetest.formspec_escape( texts[ (i*4)-1] )..']'..
				'field['..(6.2+o)..','..( 1.5+(i*1.1))..';3.9,1.0;t'..tostring((i*4)  )..';;'..
					minetest.formspec_escape( texts[ (i*4)  ] )..']'..
				'label['..(5.5+o)..','..( 1.0+(i*1.1))..';and]';
			end
		else
			-- the colors are a bit darker when offering a simple trade
			if( boxcolor=='#AAAAAA' ) then
				boxcolor = '#777777';
			elseif( boxcolor=='#0000CC' ) then
				boxcolor = '#000077';
			end
			formspec = formspec..
				'label['..(2.0+o)..','..( 2.5+(i*0.5))..';'..ltext..']'..
				'box['..(  1.8+o)..','..( 2.55+(i*0.5))..';8.1,0.51;'..boxcolor..']'..
				'field['..(3.1+o)..','..( 2.7+(i*0.5))..';7,1.0;t'..tostring((i*4)-3)..';;'..
					minetest.formspec_escape( texts[ (i*4)-3 ] )..']';
		end
	end
	minetest.show_formspec( pname, "mob_trading:trader", formspec );
end






-----------------------------------------------------------------------------------------------------
-- checks if the deptor can pay the price to the receiver (and if the receiver has enough free space)
-----------------------------------------------------------------------------------------------------
-- If the other side is an admin shop/trader with unlimited supply:
--          receiver_name has to be nil or '' and  receiver_inv has to be empty for unlmiited trade
-- The function uses recursion in case of table value for price_stack_str and calls itshelf for each price part.
mob_trading.can_trade = function( price_stack_str, debtor_name, debtor_inv, receiver_name, receiver_inv, player_is_debtor )

	-- we've got multiple items to care for
	if( type( price_stack_str )=='table' ) then
		
		-- sum up requests like 2x99 of one type or multiple requests for money
		local items = {};
		local anz_diffrent_items = 0;
		for _,v in ipairs( price_stack_str ) do
			local price_stack = ItemStack( v );
			-- get information about the price
			local price_stack_name  = price_stack:get_name();
			local price_stack_count = price_stack:get_count();
			if( not( items[ price_stack_name ])) then
				items[ price_stack_name ] = price_stack_count;
				-- lua can't count....
				anz_diffrent_items = anz_diffrent_items + 1;
			else
				items[ price_stack_name ] = items[ price_stack_name ] + price_stack_count;
			end
		end
		-- check for each part if it can be paid
		local price_desc   = '';
		local price_stacks = {};
		local price_types  = {};
		for k,v in pairs( items ) do
			-- recursively check if payment is possible
			local res = mob_trading.can_trade( k..' '..tostring( v ), debtor_name, debtor_inv, receiver_name, receiver_inv, player_is_debtor );
			-- if a part cannot be paid, the whole trade cannot be made
			if( res.error_msg ) then
				return res;
			end
			-- store the information about this part of the payment
			table.insert( price_stacks, res.price_stacks[1]);
			table.insert( price_types,  res.price_types[1] );
			-- description of first item 
			if(     price_desc == '' ) then
				price_desc = res.price_desc;
			-- cheat: this isthe last price description
			elseif( #price_stacks == anz_diffrent_items ) then
				price_desc = price_desc..' and '..res.price_desc;
			else
				price_desc = price_desc..', '..res.price_desc;
			end
		end
		-- if all parts can be paid, the whole payment will be possible
		return { error_msg = nil, price_desc = price_desc, price_stacks = price_stacks, price_types = price_types };
	end
	
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
	elseif( price_stack_name == mob_trading.MONEY_ITEM) then
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
	elseif( price_stack_name == mob_trading.MONEY2_ITEM) then
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
		return { error_msg = nil, price_desc = price_desc, price_stacks = {price_stack}, price_types = {price_type} };
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
	return { error_msg = error_msg, price_desc = price_desc, price_stacks = {price_stack}, price_types = {price_type} };
end



-----------------------------------------------------------------------------------------------------
-- moves stack from source_inv to target_inv;
--     if either does not exist, the stack is removed (i.e. with traders that are not of type individual)
-----------------------------------------------------------------------------------------------------
mob_trading.move_trade_goods = function( source_inv, target_inv, stack )

	local stacks_removed = {};

	-- in case of non-individual traders selling something, there might be no source inv
	if( source_inv ) then
		local anz = stack:get_count();
		-- large stacks may have to be split up
		while( anz > 0 ) do
			-- do not create stacks which are larger than get_stack_max
			if( stack:get_stack_max() < anz) then
				stack:set_count( stack:get_stack_max() );
			end
			local removed = source_inv:remove_item( "main", stack );
			if( not(removed) or removed:get_count() < 1 ) then
-- TODO: what to do with the partly removed items?
				return false;
			end
			anz = anz - removed:get_count();
			stack:set_count( anz );
			table.insert( stacks_removed, removed );
		end
	else
		stacks_removed = { stack };
	end

	-- non-individual traders do not store what they receive; they have no target inv
	if( not( target_inv )) then
		return true;
	end

	for i,v in pairs( stacks_removed ) do
		-- the stack may be larger than max stack size and thus require more than one add_item-call
		local remaining_stack = v;	
		while( not( remaining_stack:is_empty() )) do

			-- add as many as possible in one go
			leftover = target_inv:add_item( 'main', remaining_stack );

			-- in case nothing was added to target_inv: an error occoured (i.e. target_inv full)
			if( not( leftover:is_empty())
			    and (leftover:get_count() >= remaining_stack():get_count())) then
			-- TODO: do something more here?
minetest.chat_send_player('singleplayer','ERROR: FAILED TO ADD '..tostring( leftover:get_name()..' '..leftover:get_count()));
				return false;
			end
			remaining_stack = leftover;
		end
	end
	-- everything has been moved
	return true;
end


-----------------------------------------------------------------------------------------------------
-- check if payment and trade are possible; do the actual trade
-----------------------------------------------------------------------------------------------------
-- self ought to contain: trader_id, trader_typ, trader_owner, trader_home_pos, trader_sold (optional - for statistics)
-- traders of the type 'individual' who do have owners will search their environment for chests owned by their owner;
--      said chests contain the stock of the trader
mob_trading.do_trade = function( self, player, menu_path, trade_details )

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

		local RANGE = mob_trading.LOCKED_CHEST_SEARCH_RANGE;
		local tpos = self.object:getpos(); -- current position of the trader
		-- search for locked chest from default, locks mod and technic mod chests
		-- ignore technic mithril chests as those are not locked
		local chest_list = minetest.find_nodes_in_area(
			{ x=(tpos.x-RANGE), y=(tpos.y-RANGE), z=(tpos.z-RANGE )},
			{ x=(tpos.x+RANGE), y=(tpos.y+RANGE), z=(tpos.z+RANGE )},
			{'default:chest_locked',        'locks:shared_locked_chest', 
			 'technic:iron_locked_chest',   'technic:copper_locked_chest',
			 'technic:silver_locked_chest', 'technic:gold_locked_chest'});
		trader_inv = nil;
		for _, p in ipairs( chest_list ) do
			meta = minetest.get_meta( p );
			if( not( trader_inv) and meta and meta:get_string('owner') and meta:get_string('owner')==self.trader_owner ) then
				trader_inv = meta:get_inventory();
			end
		end

		if( not( trader_inv )) then
			return {msg='Sorry. I was unable to find my storage chest. Please contact my owner!', success=false};
		end
	end

	-- can the player pay the selected payment to the trader?
	local player_can_trade = mob_trading.can_trade( trade_details[ choice2 ], pname, player_inv, self.trader_owner, trader_inv, true );
	if( player_can_trade.error_msg ) then
		return {msg=player_can_trade.error_msg, success=false};
	end

	-- can the trader in turn give the player what the player paid for?
	local trader_can_trade = mob_trading.can_trade( trade_details[ 1       ], self.trader_owner, trader_inv, pname, player_inv, false );
	if( trader_can_trade.error_msg ) then
		return {msg=trader_can_trade.error_msg, success=false};
	end
		

	-- both sides are able to give what they agreed on - the trade may progress;
	-- traders that use money/money2 need to have an owner for their account

	-- each trade may require the exchange of multiple items
	for i,v in pairs( player_can_trade.price_types ) do
		-- the player pays first
		if(     player_can_trade.price_types[i] == 'money' ) then
			local amount = player_can_trade.price_stacks[i]:get_count();
			money.set_money( self.trader_owner, get_money( self.trader_owner ) + amount );
			money.set_money( pname,             get_money( pname )             - amount );
					
		elseif( player_can_trade.price_types[i] == 'money2' ) then
			local res = money.transfer( pname, self.trader_owner, player_can_trade.price_stacks[i]:get_count() );
			if( res ) then
				return {msg='Internal error: Payment failed: '..tostring( res )..'.', success=false};
			end
	
		elseif( player_can_trade.price_types[i] == 'direct' ) then
			local res = mob_trading.move_trade_goods( player_inv, trader_inv, player_can_trade.price_stacks[i] );
		end
	end


	for i,v in pairs( trader_can_trade.price_types ) do
		-- the trader replies
		if(     trader_can_trade.price_types[i] == 'money' ) then
			local amount = trader_can_trade.price_stacks[i]:get_count();
			money.set_money( pname,             get_money( pname )             + amount );
			money.set_money( self.trader_owner, get_money( self.trader_owner ) - amount );
					
		elseif( trader_can_trade.price_types[i] == 'money2' ) then
			local res = money.transfer( self.trader_owner, pname, trader_can_trade.price_stacks[i]:get_count() );
			if( not( res )) then
				return {msg='Internal error: Payment failed.', success=false};
			end
	
		elseif( trader_can_trade.price_types[i] == 'direct' ) then
			local res = mob_trading.move_trade_goods( trader_inv, player_inv, trader_can_trade.price_stacks[i] );
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
		' gets '..minetest.serialize( trade_details[ 1 ])..
		' for ' ..minetest.serialize( trade_details[ choice2 ])..
		' from '..tostring( self.trader_id )..
		' (owned by '..tostring( self.trader_owner )..')');


	return {msg='You got '..trader_can_trade.price_desc..' for your '..player_can_trade.price_desc..
			'.\nThank you! Would you like to trade more?', success=true};
end



