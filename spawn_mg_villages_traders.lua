
-- interface function for mg_villages;
-- the table "bed" contains all necessary information about the mob
mobf_trader.spawn_one_trader = function( bed, village_id, plot_nr, bed_nr, bpos )
	local prefix = 'trader';

	-- does the mob exist already?
	if( bed.mob_id ) then
		-- search for it
		local self = mob_basics.find_mob_by_id( bed.mob_id, 'trader' );
		if( self and self.object ) then
			-- make sure he sleeps on his assigned bed
			--mob_world_interaction.sleep_on_bed( self, bed );

			local pos_in_front_of_house = handle_schematics.get_pos_in_front_of_house( bpos, bed_nr );
			pos_in_front_of_house.y = pos_in_front_of_house.y + 1.5;
			self.object:setpos( pos_in_front_of_house );
			self.object:setyaw( math.rad( pos_in_front_of_house.yaw ));
			mob_basics.update_texture( self, 'trader', nil );
			mob_world_interaction.set_animation( self, 'stand' );

			-- return the id of the mob
			return bed.mob_id;
		end
	end


	local trader_typ = bed.title;
	if( not( trader_typ ) or trader_typ=="" or not( mob_basics.mob_types[ prefix ][ trader_typ ])) then
		trader_typ = 'teacher'; -- TODO: FALLBACK
	end

	-- try to spawn the mob
	local self = mob_basics.spawn_mob( bed, trader_typ, nil, nil, nil, nil, true );
	if( not( self )) then
		print("ERROR: NO TRADER GENERATED FOR "..minetest.pos_to_string( bed ));
		return nil;
	end

	bed.mob_id =  self[prefix..'_id'];

	-- select a texture depending on the mob's gender
	if( bed.gender == "f" ) then
		self[ prefix..'_texture' ] = "baeuerin.png";
	else
		self[ prefix..'_texture' ] = "wheat_farmer_by_addi.png";
	end
	self.object:set_properties( { textures = { self[ prefix..'_texture'] }});

	-- children are smaller
	if( bed.age < 19 ) then
		local factor = 0.2+bed.age/36;
		self[ prefix..'_vsize'] = {x=factor, y=factor, z=factor}; -- x,z:width; y: height
		mob_basics.update_visual_size( self, self[ prefix..'_vsize'], false, prefix );
	end
	-- position on bed and set sleeping animation
	--mob_world_interaction.sleep_on_bed( self, bed );

	-- place in front of the house
	local pos_in_front_of_house = handle_schematics.get_pos_in_front_of_house( bpos, bed_nr );
	pos_in_front_of_house.y = pos_in_front_of_house.y + 1.5;
	self.object:setpos( pos_in_front_of_house );
	self.object:setyaw( math.rad( pos_in_front_of_house.yaw ));
	mob_basics.update_texture( self, 'trader', nil );
	mob_world_interaction.set_animation( self, 'stand' );

	--print("SPAWNING TRADER "..trader_typ.." id: "..tostring( bed.mob_id ).." at bed "..minetest.pos_to_string( bed )); -- TODO
	return bed.mob_id;
end
