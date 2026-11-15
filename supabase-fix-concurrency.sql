-- MIGRACION: sincronizacion atomica de respuestas y puntuaciones.
-- Ejecutar UNA sola vez en Supabase > SQL Editor > New query.

create or replace function public.jsonb_set_deep(target jsonb, path text[], val jsonb)
returns jsonb language sql immutable set search_path = public
as $$
  select case
    when coalesce(array_length(path,1),0)=1
      then jsonb_set(coalesce(target,'{}'::jsonb),path,val,true)
    else jsonb_set(
      coalesce(target,'{}'::jsonb),
      array[path[1]],
      public.jsonb_set_deep(coalesce(target -> path[1],'{}'::jsonb),path[2:],val),
      true
    )
  end;
$$;

create or replace function public.patch_game_room(
  p_code text, p_path text[], p_value jsonb, p_delete boolean default false
) returns boolean
language plpgsql security invoker set search_path = public
as $$
declare v_data jsonb;
begin
  insert into public.game_rooms(code,data) values (p_code,'{}'::jsonb)
  on conflict (code) do nothing;
  select data into v_data from public.game_rooms where code=p_code for update;
  if p_delete then
    if coalesce(array_length(p_path,1),0)=0 then v_data := '{}'::jsonb;
    else v_data := v_data #- p_path; end if;
  else
    v_data := public.jsonb_set_deep(coalesce(v_data,'{}'::jsonb),p_path,coalesce(p_value,'null'::jsonb));
  end if;
  update public.game_rooms set data=v_data, updated_at=now() where code=p_code;
  return true;
end;
$$;

create or replace function public.submit_game_answer(
  p_code text, p_game text, p_round text, p_uid text, p_answer jsonb, p_points integer
) returns boolean
language plpgsql security invoker set search_path = public
as $$
declare v_data jsonb; v_answer_path text[]; v_score_path text[]; v_old numeric;
begin
  select data into v_data from public.game_rooms where code=p_code for update;
  if not found then raise exception 'Sala no encontrada'; end if;
  v_answer_path := array['answers',p_game,p_round,p_uid];
  if (v_data #> v_answer_path) is not null then return false; end if;
  v_score_path := array['scores',p_game,p_uid];
  v_old := coalesce(nullif(v_data #>> v_score_path,'')::numeric,0);
  v_data := public.jsonb_set_deep(v_data,v_answer_path,p_answer);
  if p_points <> 0 then
    v_data := public.jsonb_set_deep(v_data,v_score_path,to_jsonb(v_old+p_points));
  end if;
  update public.game_rooms set data=v_data,updated_at=now() where code=p_code;
  return true;
end;
$$;

grant execute on function public.jsonb_set_deep(jsonb,text[],jsonb) to anon, authenticated;
grant execute on function public.patch_game_room(text,text[],jsonb,boolean) to anon, authenticated;
grant execute on function public.submit_game_answer(text,text,text,text,jsonb,integer) to anon, authenticated;
