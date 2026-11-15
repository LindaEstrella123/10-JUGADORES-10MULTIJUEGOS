-- Ejecuta este archivo completo en Supabase > SQL Editor > New query.
create table if not exists public.game_rooms (
  code text primary key check (code ~ '^[A-Z0-9]{6}$'),
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.game_rooms enable row level security;
grant select, insert, update, delete on public.game_rooms to anon, authenticated;

drop policy if exists "Public can read game rooms" on public.game_rooms;
drop policy if exists "Public can create game rooms" on public.game_rooms;
drop policy if exists "Public can update game rooms" on public.game_rooms;
drop policy if exists "Public can delete game rooms" on public.game_rooms;

-- Configuración inicial sencilla para una partida privada casual.
-- El código de sala funciona como identificador, pero NO es una protección fuerte:
-- cualquiera que conozca el código podría leer o modificar el documento de esa sala.
create policy "Public can read game rooms" on public.game_rooms for select to anon, authenticated using (true);
create policy "Public can create game rooms" on public.game_rooms for insert to anon, authenticated with check (true);
create policy "Public can update game rooms" on public.game_rooms for update to anon, authenticated using (true) with check (true);
create policy "Public can delete game rooms" on public.game_rooms for delete to anon, authenticated using (true);

do $$ begin
  alter publication supabase_realtime add table public.game_rooms;
exception when duplicate_object then null;
end $$;


-- Escrituras atomicas por ruta: evita que dos jugadores sobrescriban el JSON
-- completo de la sala cuando responden casi al mismo tiempo.
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
    v_data := jsonb_set(coalesce(v_data,'{}'::jsonb),p_path,coalesce(p_value,'null'::jsonb),true);
  end if;
  update public.game_rooms set data=v_data, updated_at=now() where code=p_code;
  return true;
end;
$$;

-- Incremento de puntuación dentro de una transacción SQL.
create or replace function public.increment_game_room_score(
  p_code text, p_game text, p_uid text, p_delta numeric
) returns numeric
language plpgsql security invoker set search_path = public
as $$
declare v_data jsonb; v_old numeric; v_new numeric; v_path text[];
begin
  v_path := array['scores',p_game,p_uid];
  select data into v_data from public.game_rooms where code=p_code for update;
  if not found then raise exception 'Sala no encontrada'; end if;
  v_old := coalesce(nullif(v_data #>> v_path,'')::numeric,0);
  v_new := v_old + p_delta;
  update public.game_rooms set data=jsonb_set(v_data,v_path,to_jsonb(v_new),true),updated_at=now() where code=p_code;
  return v_new;
end;
$$;

-- Registra respuesta y suma puntos de forma atomica y solo una vez por jugador/ronda.
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
  v_data := jsonb_set(v_data,v_answer_path,p_answer,true);
  if p_points <> 0 then
    v_data := jsonb_set(v_data,v_score_path,to_jsonb(v_old+p_points),true);
  end if;
  update public.game_rooms set data=v_data,updated_at=now() where code=p_code;
  return true;
end;
$$;

grant execute on function public.patch_game_room(text,text[],jsonb,boolean) to anon, authenticated;
grant execute on function public.increment_game_room_score(text,text,text,numeric) to anon, authenticated;
grant execute on function public.submit_game_answer(text,text,text,text,jsonb,integer) to anon, authenticated;
