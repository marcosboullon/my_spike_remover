-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
-- 
-- $Id: spikeRemoverCore.sql 2009-10-01 08:00 Andreas Schmidt(andreas.schmidtATiz.bwl.de)  &  Nils Krüger(nils.kruegerATiz.bwl.de) $
--
-- spikeRemover - remove Spike from polygon
-- input Polygon geometries, angle 
-- http://www.izlbw.de/
-- Copyright 2009 Informatikzentrum Landesverwaltung Baden-Württemberg (IZLBW) Germany
-- Version 1.0
--
-- This is free software; you can redistribute and/or modify it under
-- the terms of the GNU General Public Licence. See the COPYING file.
-- This software is without any warrenty and you use it at your own risk
--  
-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

create or replace function ltspikeremovercore(geometry, angle double precision)
  returns geometry as
$body$declare
 ingeom alias for $1;
 angle  alias for $2;
 lineusp geometry;
 linenew geometry;
 newgeom geometry;
 testgeom varchar;
 remove_point boolean;
 newb boolean;
 changed boolean;
 point_id integer;
 numpoints integer;

begin
        -- input geometry or rather set as default for the output 
	newgeom := ingeom;
    
	-- check polygon
	if (select st_geometrytype(ingeom)) = 'ST_Polygon' then
	    if (select st_numinteriorrings(ingeom)) = 0 then
		
		-- default value of the loop indicates if the geometry has been changed 
		newb := true;	
                --save the polygon boundary as a line 
		lineusp := st_boundary(ingeom) as line;
		-- number of tags
		numpoints := st_numpoints(lineusp);
		-- globale changevariable 
		changed := false;

		-- loop ( to remove several points)
		while newb = true loop
		    -- default values
		    remove_point := false;
		    newb := false;
		    point_id := 0;
			

	            -- the geometry passes pointwisely
		    while (point_id <= numpoints) and (remove_point = false) loop
				-- the check of the angle at the current point of a spike including the special case, that it is the first point.
			    if (select abs(pi() - abs(st_azimuth(st_pointn(lineusp, case when point_id= 1 then st_numpoints(lineusp) - 1 else point_id - 1 end), 
	                        st_pointn(lineusp, point_id)) - st_azimuth(st_pointn(lineusp, point_id), st_pointn(lineusp, point_id + 1))))) <= angle                then
					

				    -- remove point
				    linenew := st_removepoint(lineusp, point_id - 1);

				    if linenew is not null then
						raise notice '---> remove point %', point_id;
						lineusp := linenew;
						remove_point := true; 

						-- if the first point is concerned, the last point must also be changed to close the line again.
						if point_id = 1 then
							raise notice '---> correct first point';
							linenew := st_setpoint(lineusp, numpoints - 2, st_pointn(lineusp, 1));
							lineusp := linenew;
						end if;
                    else
                        raise notice '---> no pudo eliminar el punto!';
				    end if;
			    end if;
			    point_id = point_id + 1;

		    end loop;

		    -- remove point
		    if remove_point = true then
			numpoints := st_numpoints(lineusp);
			newb := true;
			point_id := 0;
			changed := true;
		    end if;

	        end loop;
                --with the change it is tried to change back the new line geometry in a polygon. if this is not possible, the existing geometry is used
	        if changed = true then
		    newgeom :=  st_buildarea(lineusp) as geom;

		    -- errorhandling
		    if newgeom is not null then
			raise notice 'creating new geometry!';
		    else
			newgeom := ingeom;
			raise notice '-------------- area could not be created !!! --------------';
			testgeom:=st_astext(lineusp);
			raise notice 'geometry %', testgeom;
			raise notice '-------------- original --------------';
			raise notice '%', st_astext(ingeom);
		end if;
	    end if;
	end if;
    end if;
	-- return value
        return ST_RemoveRepeatedPoints (newgeom);
 end;
 $body$
  language 'plpgsql' volatile;


create or replace function lt_spikeremover(geometry, angle double precision)
  returns geometry as
$body$ 
select st_makepolygon(
        (/*outer ring of polygon*/
        select st_exteriorring(ltspikeremovercore($1,$2)) as outer_ring
          from st_dumprings($1)where path[1] = 0 
        ),  
		array(/*all inner rings*/
        select st_exteriorring(ltspikeremovercore($1, $2)) as inner_rings
          from st_dumprings($1) where path[1] > 0) 
) as geom
$body$
  language 'sql' immutable;
  
  
