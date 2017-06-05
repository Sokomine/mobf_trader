
mob_village_traders = {}

mob_village_traders.names_male = { "John", "James", "Charles", "Robert", "Joseph",
	"Richard", "David", "Michael", "Christopher", "Jason", "Matthew",
	"Joshua", "Daniel","Andrew", "Tyler", "Jakob", "Nicholas", "Ethan",
	"Alexander", "Jayden", "Mason", "Liam", "Oliver", "Jack", "Harry",
	"George", "Charlie", "Jacob", "Thomas", "Noah", "Wiliam", "Oscar",
	"Clement", "August", "Peter", "Edgar", "Calvin", "Francis", "Frank",
	"Eli", "Adam", "Samuel", "Bartholomew", "Edward", "Roger", "Albert",
	"Carl", "Alfred", "Emmett", "Eric", "Henry", "Casimir", "Alan",
	"Brian", "Logan", "Stephen", "Alexander", "Gregory", "Timothy",
	"Theodore", "Marcus", "Justin", "Julius", "Felix", "Pascal", "Jim",
	"Ben", "Zach", "Tom" };

mob_village_traders.names_female = { "Amelia", "Isla", "Ella", "Poppy", "Mia", "Mary",
	"Anna", "Emma", "Elizabeth", "Minnie", "Margret", "Ruth", "Helen",
	"Dorothy", "Betty", "Barbara", "Joan", "Shirley", "Patricia", "Judith",
	"Carol", "Linda", "Sandra", "Susan", "Deborah", "Debra", "Karen", "Donna",
	"Lisa", "Kimberly", "Michelle", "Jennifer", "Melissa", "Amy", "Heather",
	"Angela", "Jessica", "Amanda", "Sarah", "Ashley", "Brittany", "Samatha",
	"Emily", "Hannah", "Alexis", "Madison", "Olivia", "Abigail", "Isabella",
	"Ava", "Sophia", "Martha", "Rosalind", "Matilda", "Birgid", "Jennifer",
	"Chloe", "Katherine", "Penelope", "Laura", "Victoria", "Cecila", "Julia",
	"Rose", "Violet", "Jasmine", "Beth", "Stephanie", "Jane", "Jacqueline",
	"Josephine", "Danielle", "Paula", "Pauline", "Patricia", "Francesca"}

-- get a middle name for the mob
mob_village_traders.get_random_letter = function()
	return string.char( string.byte( "A") + math.random( string.byte("Z") - string.byte( "A")));
end

-- this is for medieval villages
mob_village_traders.get_family_function_str = function( data )
	if(     data.generation == 2 and data.gender=="m") then
		return "worker";
	elseif( data.generation == 2 and data.gender=="f") then
		return "wife";
	elseif( data.generation == 3 and data.gender=="m") then
		return "grandfather";
	elseif( data.generation == 3 and data.gender=="f") then
		return "grandmother";
	elseif( data.generation == 1 and data.gender=="m") then
		return "son";
	elseif( data.generation == 1 and data.gender=="f") then
		return "daughter";
	else
		return "unkown";
	end
end

mob_village_traders.get_full_trader_name = function( data )
	if( not( data ) or not( data.first_name )) then
		return;
	end
	local str = data.first_name;
	if( data.middle_name ) then
		str = str.." "..data.middle_name..".";
	end
	if( data.last_name ) then
		str = str.." "..data.last_name;
	end
	if( data.age ) then
		str = str..", age "..data.age;
	end
	-- TODO: if there is a job:   , blacksmith Fred's son   etc.
	if( data.generation and data.gender ) then
		str = str.." ("..mob_village_traders.get_family_function_str( data )..")";
	end
	return str;
end

-- TODO: store immediately where profession is determined by house type
-- TODO: shed12 and cow_shed are rather for annimals than working sheds
-- TODO: pastures are for annimals

-- TODO: in particular: there can only be one mob with the same first name and the same profession per village
-- configure a new inhabitant
-- 	gender	can be "m" or "f"
--	generation	2 for parent-generation, 1 for children, 3 for grandparents
--	name_exlcude	names the npc is not allowed to carry (=avoid duplicates)
--			(not a list but a hash table)
mob_village_traders.get_new_inhabitant = function( data, gender, generation, name_exclude )
	-- only create a new inhabitant if this one has not yet been configured
	if( not( data ) or data.first_name ) then
		return data;
	end

	-- the gender of children is random
	if( gender=="r" ) then
		if( math.random(2)==1 ) then
			gender = "m";
		else
			gender = "f";
		end
	end

	local name_list = {};
	if( gender=="f") then
		name_list = mob_village_traders.names_female;
		data.gender     = "f";   -- female
	else -- if( gender=="m" ) then
		name_list = mob_village_traders.names_male;
		data.gender     = "m";   -- male
	end
	local name_list_tmp = {};
	for i,v in ipairs( name_list ) do
		if( not( name_exclude[ v ])) then
			table.insert( name_list_tmp, v );
		end
	end
	data.first_name = name_list_tmp[ math.random(#name_list_tmp)];
	-- middle name as used in the english speaking world (might help to distinguish mobs with the same first name)
	data.middle_name = mob_village_traders.get_random_letter();

	data.generation = generation; -- 2: parent generation; 1: child; 3: grandparents
	if(     data.generation == 1 ) then
		data.age =      math.random( 18 ); -- a child
	elseif( data.generation == 2 ) then
		data.age = 18 + math.random( 30 ); -- a parent
	elseif( data.generation == 3 ) then
		data.age = 48 + math.random( 50 ); -- a grandparent
	end
	return data;
end


-- assign inhabitants to bed positions; create families;
-- bpos needs to contain at least { beds = {list_of_bed_positions}, btye = building_type}
mob_village_traders.assing_mobs_to_beds = function( bpos )

	if( not( bpos ) or not( bpos.btype )) then
		return bpos;
	end

	-- get data about the building
	local building_data = mg_villages.BUILDINGS[ bpos.btype ];
	-- the building type determines which kind of traders will live there
	if( not( building_data ) or not( building_data.typ )
	   -- are there beds where the mob can sleep?
	   or not( bpos.beds ) or table.getn( bpos.beds ) < 1) then
		return bpos;
	end

	-- lumberjack home
	if( building_data.typ == "lumberjack" ) then

		for i,v in ipairs( bpos.beds ) do
			-- lumberjacks do not have families and are all male
			v = mob_village_traders.get_new_inhabitant( v, "m", 2, {} );
		end

	-- normal house containing a family
	else
		-- the first inhabitant will be the male worker
		if( not( bpos.beds[1].first_name )) then
			bpos.beds[1] = mob_village_traders.get_new_inhabitant( bpos.beds[1], "m", 2, {} ); -- male of parent generation
		end

		local name_exclude = {};
		-- the second inhabitant will be the wife of the male worker
		if( bpos.beds[2] and not( bpos.beds[2].first_name )) then
			bpos.beds[2] = mob_village_traders.get_new_inhabitant( bpos.beds[2], "f", 2, {} ); -- female of parent generation
			-- first names ought to be uniq withhin a family
			name_exclude[ bpos.beds[2].first_name ] = 1;
		end

		-- not all houses will have grandparents
		local grandmother_bed_id = 2+math.random(5);
		local grandfather_bed_id = 2+math.random(5);
		-- a child of 18 with a parent of 19 would be...usually impossible unless adopted
		local oldest_child = 0;

		-- the third and subsequent inhabitants will ether be children or grandparents
		for i,v in ipairs( bpos.beds ) do
			-- at max 7 npc per house (taverns may have more beds than that)
			if( v and not( v.first_name ) and i<8) then
				if(     i==grandmother_bed_id ) then
					v = mob_village_traders.get_new_inhabitant( v, "f", 3, name_exclude ); -- get the grandmother
				elseif( i==grandfather_bed_id ) then
					v = mob_village_traders.get_new_inhabitant( v, "m", 3, name_exclude ); -- get the grandfather
				else
					v = mob_village_traders.get_new_inhabitant( v, "r", 1, name_exclude ); -- get a child of random gender
					-- find out how old the oldest child is
					if( v.age > oldest_child ) then
						oldest_child = v.age;
					end
				end
				-- children and grandparents need uniq names withhin a family
				name_exclude[ v.first_name ] = 1;
			end
		end
		-- the father has to be old enough for his children
		if( bpos.beds[1] and oldest_child + 18 > bpos.beds[1].age ) then
			bpos.beds[1].age = oldest_child + 18 + math.random( 10 );
		end
		-- the mother also has to be old enough as well
		if( bpos.beds[2] and oldest_child + 18 > bpos.beds[2].age ) then
			bpos.beds[2].age = oldest_child + 18 + math.random( 10 );
		end
	end

	-- TODO: only for debugging
	local str = "HOUSE "..tostring( building_data.typ ).." is inhabitated by:\n";
	for i,v in ipairs( bpos.beds ) do
		if( v and v.first_name ) then
			str = str.." "..mob_village_traders.get_full_trader_name( v ).."\n";
		end
	end
	print( str );

	return bpos;
end


-- spawn traders in villages
mob_village_traders.part_of_village_spawned = function( village, minp, maxp, data, param2_data, a, cid )
	-- if mobf_trader is not installed, we can't spawn any mobs;
	-- if mg_villages is not installed, we do not need to spawn anything
	if(   not( minetest.get_modpath( 'mobf_trader'))
	   or not( minetest.get_modpath( 'mg_villages'))
	   or not( mob_basics )
	   or not( mob_basics.spawn_mob )) then
		return;
	end

	-- diffrent villages may have diffrent traders
	local village_type  = village.village_type;

	-- for each building in the village
	for i,bpos in pairs(village.to_add_data.bpos) do

		-- only handle buildings that are at least partly contained in that part of the
		-- village that got spawned in this mapchunk
		-- if further parts of the house spawn in diffrent mapchunks, the new beds will be
		-- checked and populated with further inhabitants
		if( not(  bpos.x > maxp.x or bpos.x + bpos.bsizex < minp.x
		       or bpos.z > maxp.z or bpos.z + bpos.bsizez < minp.z )) then

			bpos = mob_village_traders.assing_mobs_to_beds( bpos );
		end
--[[
		   -- avoid spawning them twice
		   and not( bpos.traders )) then

print("ASSIGNING TO "..tostring(building_data.typ).." WITH beds "..minetest.serialize( bpos.beds ));
			-- choose traders; the replacements may be relevant:
			-- wood traders tend to sell the same wood type of which their house is built
			local traders = mob_village_traders.choose_traders( village_type, building_data.typ, village.to_add_data.replacements );

			-- find spawn positions for all traders in the list
			local all_pos = mob_village_traders.choose_trader_pos(bpos, minp, maxp, data, param2_data, a, cid, traders);

			-- actually spawn the traders
			for _,v in ipairs( all_pos ) do
				mob_basics.spawn_mob( {x=v.x, y=v.y, z=v.z}, v.typ, nil, nil, nil, nil, true );
			end

			-- store the information about the spawned traders
			village.to_add_data.bpos[ i ].traders = all_pos;
--]]
	end
end


mob_village_traders.choose_traders = function( village_type, building_type, replacements )

	if( not( building_type ) or not( village_type )) then
		return {};
	end
	
	-- some jobs are obvious
	if(     building_type == 'mill' ) then
		return { 'miller' };
	elseif( building_type == 'bakery' ) then
		return { 'baker' };
	elseif( building_type == 'school' ) then
		return { 'teacher' };
	elseif( building_type == 'forge' ) then
		local traders = {'blacksmith', 'bronzesmith',
			'goldsmith', 'bladesmith', 'locksmith', 'coppersmith', 'silversmith', 'tinsmith' }; -- TODO: does not exist yet
		return { traders[ math.random(#traders)] };
	elseif( building_type == 'shop' ) then
		local traders = {'seeds','flowers','misc','default','ore', 'fruit trader', 'wood'};
		return { traders[ math.random(#traders)] };
	elseif( building_type == 'church' ) then
		return { 'priest' }; -- TODO: does not exist yet
	elseif( building_type == 'tower' ) then
		return { 'guard' }; -- TODO: does not exist yet  -- TODO: really only one guard per village?
	elseif( building_type == 'library' ) then
		return { 'librarian' }; -- TODO: does not exist yet
	elseif( building_type == 'tavern' ) then
		return { 'barkeeper'}; -- TODO: does not exist yet
	end

	if(     village_type == 'charachoal' ) then
		return { 'charachoal' };
	elseif( village_type == 'claytrader' ) then
		return { 'clay' };
	end

	local res = {};
	if(   building_type == 'shed' -- TODO: workers from the houses may work here
	   or building_type == 'farm_tiny' 
	   or building_type == 'house'
	   or building_type == 'house_large'
	   or building_type=='hut') then
		local traders = { 'stonemason', 'stoneminer', 'carpenter', 'toolmaker',
			'doormaker', 'furnituremaker', 'stairmaker', 'cooper', 'wheelwright',
			'saddler', 'roofer', 'iceman', 'potterer', 'bricklayer', 'dyemaker',
			'dyemakerl', 'glassmaker' }
		-- sheds and farms both contain craftmen
		res = { traders[ math.random( #traders )] };
		if(    building_type == 'shed'
		    or building_type == 'house'
		    or building_type == 'house_large'
		    or building_type == 'hut' ) then
			return res;
		end
	end

	if(   building_type == 'field'
	   or building_type == 'farm_full'
	   or building_type == 'farm_tiny' ) then

		local fruit = 'farming:cotton';
		if( 'farm_full' ) then
			-- RealTest
			fruit = 'farming:wheat';
			if( replacements_group['farming'].traders[ 'farming:soy']) then
				fruit = 'farming:soy';
			end
			if( minetest.get_modpath("mobf") ) then
				local animal_trader = {'animal_cow', 'animal_sheep', 'animal_chicken', 'animal_exotic'};
				res[1] = animal_trader[ math.random( #animal_trader )];	
			end
			return { res[1], replacements_group['farming'].traders[ fruit ]};
		elseif( #replacements_group['farming'].found > 0 ) then
			-- get a random fruit to grow
			fruit = replacements_group['farming'].found[ math.random( #replacements_group['farming'].found) ];
			return { res[1], replacements_group['farming'].traders[ fruit ]};
		else
			return res;
		end
	end

	if( building_type == 'pasture' and minetest.get_modpath("mobf")) then
		local animal_trader = {'animal_cow', 'animal_sheep', 'animal_chicken', 'animal_exotic'};
		return { animal_trader[ math.random( #animal_trader )] };
	end	


	-- TODO: banana,cocoa,rubber from farming_plus?
	-- TODO: sawmill
	if( building_type == 'lumberjack' or village_type == 'lumberjack' ) then
		-- find the wood replacement
		local wood_replacement = 'default:wood';
		for _,v in ipairs( replacements ) do
			if( v and v[1]=='default:wood' ) then
				wood_replacement = v[2];
			end
		end
		-- lumberjacks are more likely to sell the wood of the type of house they are living in
		if( wood_replacement and math.random(1,3)==1) then
			return { replacements_group['wood'].traders[ wood_replacement ]};
		-- ...but not exclusively
		elseif( replacements_group['wood'].traders ) then
			-- construct a list containing all available wood trader types
			local list = {};
			for k,v in pairs( replacements_group['wood'].traders ) do
				list[#list+1] = k;
			end
			return { replacements_group['wood'].traders[ list[ math.random( 1,#list )]]};
		-- fallback
		else
			return { 'common_wood'};
		end

	-- TODO: trader, pit (in claytrader villages)
	end

	
	-- tent, chateau: places for living at; no special jobs associated
	-- TODO: chateau: may have a servant
	-- nore,taoki,medieval,lumberjack,logcabin,canadian,grasshut,tent: further village types

	return res;
end


-- chooses trader positions for multiple traders for one particular building
mob_village_traders.choose_trader_pos = function(pos, minp, maxp, data, param2_data, a, cid, traders)

	local trader_pos = {};
	-- determine spawn positions for the mobs
	for i,tr in ipairs( traders ) do
		local tries = 0;
		local found = false;
		local pt = {x=pos.x, y=pos.y-1, z=pos.z};
		while( tries < 20 and not(found)) do
			-- get a random position for the trader
			pt.x = (pos.x-1)+math.random(0,pos.bsizex+1);
			pt.z = (pos.z-1)+math.random(0,pos.bsizez+1);
			-- check if it is inside the area contained in data
			if (pt.x >= minp.x and pt.x <= maxp.x) and (pt.y >= minp.y and pt.y <= maxp.y) and (pt.z >= minp.z and pt.z <= maxp.z) then

				while( pt.y < maxp.y 
				  and (data[ a:index( pt.x, pt.y,   pt.z)]~=cid.c_air
				    or data[ a:index( pt.x, pt.y+1, pt.z)]~=cid.c_air )) do
					pt.y = pt.y + 1;
				end

				-- check if this position is really suitable? traders standing on the roof are a bit odd
				local node_id = data[ a:index( pt.x, pt.y-1, pt.z)];
				local def = {};
				if( node_id and minetest.get_name_from_content_id( node_id )) then
					def = minetest.registered_nodes[ minetest.get_name_from_content_id( node_id)];
				end
				if( not(def) or not(def.drawtype) or def.drawtype=="nodebox" or def.drawtype=="mesh" or def.name=='air') then
					found = false;
				elseif( def and def.name ) then
					found = true;
				end
			end
			tries = tries+1;

			-- check if this position has already been assigned to another trader
			for j,t in ipairs( trader_pos ) do
				if( t.x==pt.x and t.y==pt.y and t.z==pt.z ) then
					found = false;
				end
			end
		end

		-- there is usually free space around the building; use that for spawning
		if( found==false ) then
			if( pt.x < minp.x ) then
				pt.x = pos.x + pos.bsizex+1;
			else
				pt.x = pos.x-1;
			end
			pt.z = pos.z-1 + math.random( pos.bsizez+1 );
			-- let the trader drop down until he finds ground
			pt.y = pos.y + 20;
			found = true;
		end

		table.insert( trader_pos, {x=pt.x, y=pt.y, z=pt.z, typ=tr} );
	end
	return trader_pos;
end
