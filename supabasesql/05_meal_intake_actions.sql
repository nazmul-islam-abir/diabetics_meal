-- ============================================================
-- Amar Diet — extra schema for todo-list tracking + portions
-- Apply AFTER 01_schema.sql, 02_rpcs.sql, 03_seed_foods.sql, 04_seed_alternatives.sql
-- ============================================================

-- ---------- 7. EXPAND meal_intake_log ----------
-- Add a column to know which item from the plan this log entry corresponds to
-- (so the same food can be logged multiple times per day as different slots).
alter table public.meal_intake_log
  add column if not exists plan_day int,
  add column if not exists meal_slot_index int,
  add column if not exists impact_reason text;

-- Optional: a "deleted" flag so users can undo
alter table public.meal_intake_log
  add column if not exists hidden boolean not null default false;

create index if not exists meal_intake_log_user_date_slot
  on public.meal_intake_log (user_id, meal_date, meal_slot);

-- ---------- 8. USER RECIPES (saved swaps) ----------
-- Lets a user save a swap they made often (e.g., "I always eat ruti instead of oats").
create table if not exists public.user_recipes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  meal_slot text not null,
  food_id text not null references public.foods(id) on delete cascade,
  notes text,
  created_at timestamptz not null default now()
);

alter table public.user_recipes enable row level security;
drop policy if exists "Users manage their own recipes" on public.user_recipes;
create policy "Users manage their own recipes"
  on public.user_recipes for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------- 9. UPDATED record_meal_intake (accepts plan_day + reason) ----------
create or replace function public.record_meal_intake(
  p_meal_slot text,
  p_food_id text,
  p_food_name_bn text,
  p_status text,
  p_impact text,
  p_notes text default null,
  p_plan_day int default null,
  p_reason text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  insert into public.meal_intake_log
    (user_id, meal_slot, food_id, food_name_bn, status, impact, notes, plan_day, impact_reason)
  values
    (v_user, p_meal_slot, p_food_id, p_food_name_bn, p_status, p_impact, p_notes, p_plan_day, p_reason)
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------- 10. UNDO (hide) a meal log entry ----------
create or replace function public.hide_meal_intake(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  update public.meal_intake_log set hidden = true
    where id = p_id and user_id = v_user;
end;
$$;

-- ---------- 11. WEEKLY NUTRITION ROLLUP ----------
-- Returns aggregate macros for the last N days based on what the user actually ate.
-- If a food was eaten as a "swap" or "off_plan", we still count its real macros.
-- If a planned food was skipped, it's not counted.
create or replace function public.get_weekly_nutrition(p_days int default 7)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_carb numeric := 0;
  v_protein numeric := 0;
  v_fat numeric := 0;
  v_fiber numeric := 0;
  v_sodium numeric := 0;
  v_k numeric := 0;
  v_phos numeric := 0;
  r record;
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  for r in
    select l.food_id, l.impact
    from public.meal_intake_log l
    where l.user_id = v_user
      and l.hidden = false
      and l.meal_date >= ((now() at time zone 'Asia/Dhaka')::date - (p_days - 1))
  loop
    if r.food_id is null then continue; end if;
    select carb_g, protein_g, fat_g, fiber_g, sodium_mg, potassium_mg, phosphorus_mg
      into v_carb, v_protein, v_fat, v_fiber, v_sodium, v_k, v_phos
      from public.foods where id = r.food_id;
    if not found then continue; end if;
    -- accumulator logic done in plain sql using select sum below
  end loop;

  select coalesce(sum(f.carb_g), 0),
         coalesce(sum(f.protein_g), 0),
         coalesce(sum(f.fat_g), 0),
         coalesce(sum(f.fiber_g), 0),
         coalesce(sum(f.sodium_mg), 0),
         coalesce(sum(f.potassium_mg), 0),
         coalesce(sum(f.phosphorus_mg), 0)
    into v_carb, v_protein, v_fat, v_fiber, v_sodium, v_k, v_phos
  from public.meal_intake_log l
  join public.foods f on f.id = l.food_id
  where l.user_id = v_user
    and l.hidden = false
    and l.meal_date >= ((now() at time zone 'Asia/Dhaka')::date - (p_days - 1));

  return jsonb_build_object(
    'days', p_days,
    'carb_g', v_carb,
    'protein_g', v_protein,
    'fat_g', v_fat,
    'fiber_g', v_fiber,
    'sodium_mg', v_sodium,
    'potassium_mg', v_k,
    'phosphorus_mg', v_phos
  );
end;
$$;
