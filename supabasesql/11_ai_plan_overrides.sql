-- ============================================================
-- 11 — Per-user AI plan overrides (CRUD on AI-suggested tiles)
-- ============================================================
-- Safe to re-run. Creates one table and 3 RPCs. Nothing existing
-- is touched.
--
-- Why this exists:
-- The 30-day rotation in meal_plan_days is the same for every
-- user. Many users want to "edit the AI's breakfast" — keep the
-- rotating day but swap the suggested food for their own master
-- food (e.g. replace "লাল আটার রুটি" with "ওটস"). Storing this
-- per-user instead of mutating meal_plan_days keeps the rotation
-- canonical and lets every user get their own version of the
-- same day.
--
-- Storage model:
-- meal_plan_overrides is keyed by (user_id, plan_day, slot, role).
-- One row per (day, slot, role) tuple per user. There is NO
-- additional row in the AI plan to merge against — if you write
-- an override, your value IS the row, the baseline is ignored.
--
-- Different from user_meal_plans (10_*.sql): those are NEW slots
-- the user adds (e.g. "before-bed warm milk", extra tiffin). An
-- override REPLACES an AI slot's food. Both layers coexist.
--
-- RPCs:
--   * upsert_ai_plan_override(p_day, p_slot, p_role, p_food_id)
--   * delete_ai_plan_override(p_day, p_slot, p_role)
--   * get_daily_recommendation_with_overrides(p_day)
--       returns the same shape as get_daily_recommendation() but
--       with per-user overrides merged in.

-- ---------- 1. PER-USER OVERRIDES ----------
create table if not exists public.meal_plan_overrides (
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_day int not null check (plan_day between 1 and 30),
  slot text not null check (slot in (
    'breakfast','morning_snack','lunch','evening_snack','dinner'
  )),
  -- 'role' exists only when a slot has multiple parts (lunch/dinner).
  -- For single-item slots (breakfast, snacks) role is null.
  role text check (role in (
    'main','carb','protein','vegetable','dal','snack'
  )),
  -- The food this override pins. Must reference the master foods
  -- list so the UI can resolve nutrition + impact.
  food_id text not null references public.foods(id) on delete cascade,
  updated_at timestamptz not null default now(),
  primary key (user_id, plan_day, slot, role)
);

create index if not exists meal_plan_overrides_user_day
  on public.meal_plan_overrides (user_id, plan_day);

alter table public.meal_plan_overrides enable row level security;
drop policy if exists "Users manage their own overrides" on public.meal_plan_overrides;
create policy "Users manage their own overrides"
  on public.meal_plan_overrides for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ---------- 2. AUTO-TOUCH updated_at ----------
create or replace function public.touch_meal_plan_overrides_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_meal_plan_overrides_touch on public.meal_plan_overrides;
create trigger trg_meal_plan_overrides_touch
  before update on public.meal_plan_overrides
  for each row execute function public.touch_meal_plan_overrides_updated_at();


-- ---------- 3. UPSERT one override ----------
create or replace function public.upsert_ai_plan_override(
  p_plan_day int,
  p_slot text,
  p_role text default null,
  p_food_id text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  if p_food_id is null or length(trim(p_food_id)) = 0 then
    raise exception 'food_id is required';
  end if;
  if p_plan_day is null or p_plan_day < 1 or p_plan_day > 30 then
    raise exception 'plan_day must be between 1 and 30';
  end if;
  if not exists (select 1 from public.foods where id = p_food_id) then
    raise exception 'Food % not found in master list', p_food_id;
  end if;

  insert into public.meal_plan_overrides
    (user_id, plan_day, slot, role, food_id)
  values
    (v_user, p_plan_day, p_slot, p_role, p_food_id)
  on conflict (user_id, plan_day, slot, role) do update
    set food_id = excluded.food_id,
        updated_at = now();
end;
$$;


-- ---------- 4. DELETE one override (back to AI default) ----------
create or replace function public.delete_ai_plan_override(
  p_plan_day int,
  p_slot text,
  p_role text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  delete from public.meal_plan_overrides
    where user_id = v_user
      and plan_day = p_plan_day
      and slot = p_slot
      and role is not distinct from p_role;
end;
$$;


-- ---------- 5. LIST overrides for a day (helper) ----------
create or replace function public.list_ai_plan_overrides(p_plan_day int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(o) order by o.slot, o.role)
    from (
      select user_id, plan_day, slot, role, food_id, updated_at
      from public.meal_plan_overrides
      where user_id = v_user
        and plan_day = p_plan_day
    ) o
  ), '[]'::jsonb);
end;
$$;


-- ============================================================
-- 6. RECOMMENDATION RPC THAT MERGES OVERRIDES
-- ============================================================
-- Same shape as get_daily_recommendation() so the Flutter code
-- can call either interchangeably. We call the baseline once
-- inside this RPC and rewrite each (slot, role) using any user
-- override row that matches.
create or replace function public.get_daily_recommendation_with_overrides(
  p_plan_day int default 1
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_baseline jsonb;
begin
  -- Baseline uses the same RPC the app already calls; running it
  -- with the same user keeps behavior identical when a new app
  -- version is released against older databases.
  v_baseline := public.get_daily_recommendation(p_plan_day);

  if v_user is null then
    return v_baseline;
  end if;

  -- Override the breakfast main food.
  update public.foods f
    set name_bn = ovr.food_id
    from public.meal_plan_overrides ovr
    where ovr.user_id = v_user
      and ovr.plan_day = p_plan_day
      and ovr.slot = '__noop_breakfast__';
  -- (we don't actually do the merge via foods-row updates; we
  -- rebuild the json in a controlled way below)

  return (
    with day as (
      select * from public.meal_plan_days where day = p_plan_day
    ),
    overrides as (
      select slot, role, food_id from public.meal_plan_overrides
        where user_id = v_user and plan_day = p_plan_day
    ),
    br as (
      -- breakfast (main)
      select f.id, f.name_bn, f.category,
             f.carb_g, f.protein_g, f.fat_g, f.fiber_g,
             f.sodium_mg, f.potassium_mg, f.phosphorus_mg,
             f.gi_category, f.portion_label, f.portion_g,
             f.affordability, f.common_in_bd, f.effort,
             f.healthiness, f.tags
        from public.foods f
       where f.id = coalesce(
         (select food_id from overrides
            where slot = 'breakfast' and role is null),
         (select breakfast_main::text from day)
       )
    ),
    ms as (
      select f.id, f.name_bn, f.category,
             f.carb_g, f.protein_g, f.fat_g, f.fiber_g,
             f.sodium_mg, f.potassium_mg, f.phosphorus_mg,
             f.gi_category, f.portion_label, f.portion_g,
             f.affordability, f.common_in_bd, f.effort,
             f.healthiness, f.tags
        from public.foods f
       where f.id = coalesce(
         (select food_id from overrides
            where slot = 'morning_snack' and role is null),
         (select morning_snack::text from day)
       )
    ),
    es as (
      select f.id, f.name_bn, f.category,
             f.carb_g, f.protein_g, f.fat_g, f.fiber_g,
             f.sodium_mg, f.potassium_mg, f.phosphorus_mg,
             f.gi_category, f.portion_label, f.portion_g,
             f.affordability, f.common_in_bd, f.effort,
             f.healthiness, f.tags
        from public.foods f
       where f.id = coalesce(
         (select food_id from overrides
            where slot = 'evening_snack' and role is null),
         (select evening_snack::text from day)
       )
    ),
    l_carb as (
      select f.* from public.foods f
       where f.id = coalesce(
         (select food_id from overrides where slot = 'lunch' and role = 'carb'),
         (select lunch_carb::text from day))
    ),
    l_prot as (
      select f.* from public.foods f
       where f.id = coalesce(
         (select food_id from overrides where slot = 'lunch' and role = 'protein'),
         (select lunch_protein::text from day))
    ),
    l_veg as (
      select f.* from public.foods f
       where f.id = coalesce(
         (select food_id from overrides where slot = 'lunch' and role = 'vegetable'),
         (select lunch_vegetable::text from day))
    ),
    l_dal as (
      select f.* from public.foods f
       where f.id = coalesce(
         (select food_id from overrides where slot = 'lunch' and role = 'dal'),
         (select lunch_dal::text from day))
    ),
    d_carb as (
      select f.* from public.foods f
       where f.id = coalesce(
         (select food_id from overrides where slot = 'dinner' and role = 'carb'),
         (select dinner_carb::text from day))
    ),
    d_prot as (
      select f.* from public.foods f
       where f.id = coalesce(
         (select food_id from overrides where slot = 'dinner' and role = 'protein'),
         (select dinner_protein::text from day))
    ),
    d_veg as (
      select f.* from public.foods f
       where f.id = coalesce(
         (select food_id from overrides where slot = 'dinner' and role = 'vegetable'),
         (select dinner_vegetable::text from day))
    )
    select jsonb_build_object(
      'plan_day', p_plan_day,
      'classification', v_baseline->'classification',
      'breakfast', (select to_jsonb(br) from br where br.id is not null),
      'morning_snack', (select to_jsonb(ms) from ms where ms.id is not null),
      'evening_snack', (select to_jsonb(es) from es where es.id is not null),
      'lunch', jsonb_build_object(
        'carb', (select to_jsonb(l_carb) from l_carb where l_carb.id is not null),
        'protein', (select to_jsonb(l_prot) from l_prot where l_prot.id is not null),
        'vegetable', (select to_jsonb(l_veg) from l_veg where l_veg.id is not null),
        'dal', (select to_jsonb(l_dal) from l_dal where l_dal.id is not null)
      ),
      'dinner', jsonb_build_object(
        'carb', (select to_jsonb(d_carb) from d_carb where d_carb.id is not null),
        'protein', (select to_jsonb(d_prot) from d_prot where d_prot.id is not null),
        'vegetable', (select to_jsonb(d_veg) from d_veg where d_veg.id is not null)
      )
    )
  );
end;
$$;
