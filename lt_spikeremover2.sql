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
-- Corregida por LaboraTe, febrero 2015
-- PostGIS 2
-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

create or replace function ltspikeremovercore2(geometry, angle double precision)
    returns geometry as
$body$
declare
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

            -- geometry has been changed?
            newb := true;

            -- polygon boundary
            lineusp := st_boundary(ingeom) as line;

            -- number of points
            numpoints := st_numpoints(lineusp);

            -- global change variable
            changed := false;

            -- loop (to remove several points)
            while newb = true loop

                -- default values
                remove_point := false;
                newb := false;
                point_id := 0;

                -- the geometry passes pointwisely
                while (point_id <= numpoints) and (remove_point = false) loop

                    -- raise notice '-- info -- point %', point_id;

                    -- the check of the angle at the current point of a spike
                    if (select abs(pi() - abs(st_azimuth(st_pointn(lineusp,
                        case when point_id = 1 then st_numpoints(lineusp) - 1 else point_id - 1 end
                        ), st_pointn(lineusp, point_id)) - st_azimuth(st_pointn(lineusp, point_id),
                        st_pointn(lineusp, point_id + 1))))) <= angle
                    then

                        -- raise notice '-- info -- spike detected at point % and removing the previous one', point_id;

                        if numpoints > 4 then
                            -- remove point
                            linenew := st_removepoint(lineusp, point_id - 1);
                            if linenew is not null then
                                -- raise notice '-- info -- removed';
                                lineusp := linenew;
                                remove_point := true; 

                                -- correct first point
                                if point_id = 1 then
                                    -- raise notice '-- info -- trying to correct first point';
                                    linenew := st_setpoint(lineusp, numpoints - 2, st_pointn(lineusp, 1));
                                    if linenew is not null then
                                        -- raise notice '-- info -- corrected';
                                        lineusp := linenew;
                                    else
                                        raise notice '-- error -- unable to correct first point';
                                        return null;
                                    end if;
                                end if;
                            else
                                raise notice '-- error -- unable to remove point';
                                return null;
                            end if;
                        else
                            raise notice '-- error -- unable to remove anything in a four-points geometry';
                            return null;
                        end if;
                    end if;

                    point_id = point_id + 1;

                end loop;

                -- raise notice '-- info -- loop finished';

                -- point removed
                if remove_point = true then
                    -- raise notice '-- info -- some points removed in loop: correct and retry loop';
                    numpoints := st_numpoints(lineusp);
                    newb := true;
                    point_id := 0;
                    changed := true;
                else
                    -- raise notice '-- info -- no points removed in loop: exit';
                end if;

            end loop;

            -- raise notice '-- info -- exterior loop finished: no more changes scheduled';

            if changed = true then
                -- raise notice '-- info -- changes happened: change geometry';
                --newgeom :=  st_buildarea(lineusp) as geom;
                newgeom := st_makepolygon(lineusp) as geom;

                -- error handling
                if newgeom is not null then
                    -- raise notice '-- info -- creating new geometry!';
                else
                    newgeom := ingeom;
                    raise notice '-- error -- unable to create new geometry';
                    raise notice '-- geometry -- %', st_astext(lineusp);
                    return null;
                end if;
            else
                -- raise notice '-- info -- no changes happened';
            end if;
        else
            raise notice '-- error -- geometry still has interior rings';
            return null;
        end if;
    else
        raise notice '-- error -- geometry is not a POLYGON';
        return null;
    end if;

    -- return value
    return ST_RemoveRepeatedPoints (newgeom);
end;
$body$
language 'plpgsql' volatile;


create or replace function lt_spikeremover2(geometry, angle double precision)
returns geometry as
$body$ 
select st_makepolygon(
        (/*outer ring of polygon*/
        select st_exteriorring(ltspikeremovercore2($1, $2)) as outer_ring
          from st_dumprings($1)where path[1] = 0 
        ),  
		array(/*all inner rings*/
        select st_exteriorring(ltspikeremovercore2($1, $2)) as inner_rings
          from st_dumprings($1) where path[1] > 0) 
) as geom
$body$
language 'sql' immutable;

