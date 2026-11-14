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
