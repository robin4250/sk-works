-- REVIEW ONLY. New inputs only; never replace the historical has_signature helper.
create schema signature_new_input_private;
revoke all on schema signature_new_input_private from public,anon,authenticated,service_role;
create function signature_new_input_private.require_ink(p_value jsonb)
returns void language plpgsql immutable set search_path='' as $$
declare strokes jsonb;stroke jsonb;point jsonb;keys text[];has_ink boolean:=false;
 total_points integer:=0;with_dimensions boolean;dimensions_mode boolean;
 width_value numeric:=400;height_value numeric:=120;px double precision;py double precision;
 previous_x double precision;previous_y double precision;line_length double precision;
begin
 if p_value is null or jsonb_typeof(p_value) is distinct from 'object' or octet_length(p_value::text)>4194304 then
  raise sqlstate '22023' using message='new_signature_input_invalid';end if;
 select array_agg(k order by k) into keys from jsonb_object_keys(p_value) k;
 if keys is distinct from array['strokes']::text[] or jsonb_typeof(p_value->'strokes') is distinct from 'array' then
  raise sqlstate '22023' using message='new_signature_input_invalid';end if;
 strokes:=p_value->'strokes';
 if jsonb_array_length(strokes)=0 or jsonb_array_length(strokes)>256 then
  raise sqlstate '22023' using message='new_signature_input_invalid';end if;
 for stroke in select value from jsonb_array_elements(strokes) loop
  if jsonb_typeof(stroke) is distinct from 'array' or jsonb_array_length(stroke)=0 or jsonb_array_length(stroke)>16384 then
   raise sqlstate '22023' using message='new_signature_input_invalid';end if;
  previous_x:=null;previous_y:=null;line_length:=0;
  for point in select value from jsonb_array_elements(stroke) loop
   total_points:=total_points+1;
   if total_points>65536 or jsonb_typeof(point) is distinct from 'object' then
    raise sqlstate '22023' using message='new_signature_input_invalid';end if;
   select array_agg(k order by k) into keys from jsonb_object_keys(point) k;
   if keys is distinct from array['x','y']::text[] and keys is distinct from array['canvas_height','canvas_width','x','y']::text[] then
    raise sqlstate '22023' using message='new_signature_input_invalid';end if;
   if jsonb_typeof(point->'x') is distinct from 'number' or jsonb_typeof(point->'y') is distinct from 'number'
    or not ((point->>'x')::numeric between 0 and 1) or not ((point->>'y')::numeric between 0 and 1) then
    raise sqlstate '22023' using message='new_signature_input_invalid';end if;
   with_dimensions:=point?'canvas_width';
   if dimensions_mode is null then dimensions_mode:=with_dimensions;
   elsif dimensions_mode is distinct from with_dimensions then raise sqlstate '22023' using message='new_signature_input_invalid';end if;
   if with_dimensions then
    if jsonb_typeof(point->'canvas_width') is distinct from 'number' or jsonb_typeof(point->'canvas_height') is distinct from 'number'
     or not ((point->>'canvas_width')::numeric>0 and (point->>'canvas_width')::numeric<=16384)
     or not ((point->>'canvas_height')::numeric>0 and (point->>'canvas_height')::numeric<=16384) then
     raise sqlstate '22023' using message='new_signature_input_invalid';end if;
    if total_points=1 then width_value:=(point->>'canvas_width')::numeric;height_value:=(point->>'canvas_height')::numeric;
    elsif width_value is distinct from (point->>'canvas_width')::numeric or height_value is distinct from (point->>'canvas_height')::numeric then
     raise sqlstate '22023' using message='new_signature_input_invalid';end if;
   end if;
   px:=(point->>'x')::double precision;py:=(point->>'y')::double precision;
   if previous_x is not null then
    line_length:=line_length+sqrt(power((px-previous_x)*width_value::double precision,2)+power((py-previous_y)*height_value::double precision,2));
    if line_length>=1 then has_ink:=true;end if;
   end if;
   previous_x:=px;previous_y:=py;
  end loop;
 end loop;
 if not has_ink then raise sqlstate '22023' using message='new_signature_visible_stroke_required';end if;
end $$;
create function signature_new_input_private.require_financial_signature(p_value jsonb)
returns void language plpgsql immutable set search_path='' as $$
declare keys text[];
begin
 if p_value is null or jsonb_typeof(p_value) is distinct from 'object' or octet_length(p_value::text)>4194304 then
  raise sqlstate '22023' using message='new_signature_input_invalid';end if;
 select array_agg(k order by k) into keys from jsonb_object_keys(p_value) k;
 if keys=array['strokes']::text[] then perform signature_new_input_private.require_ink(p_value);
 elsif keys=array['representative','supervisor','version']::text[] and p_value->'version'='3'::jsonb then
  perform signature_new_input_private.require_ink(p_value->'representative');
  perform signature_new_input_private.require_ink(p_value->'supervisor');
 else raise sqlstate '22023' using message='new_signature_input_invalid';end if;
end $$;
revoke all on all functions in schema signature_new_input_private from public,anon,authenticated,service_role;
