-- ============================================================
-- 09 — Honor food_preference in daily recommendations
-- ============================================================
-- Safe to re-run. Only side effects: replaces two helper functions
-- (food_category, pick_for_preference) and one RPC
-- (get_daily_recommendation). No tables, columns, or rows are dropped.
--
-- The planner was returning the raw 30-day rotation regardless of
-- the user's food_preference. This script routes every protein /
-- dal slot through a preference-aware picker before lookup.

-- ---------- 0. Drop stale versions from any previous run ----------
-- Postgres refuses CREATE OR REPLACE on a function whose parameter
-- names changed, and refuses to overload-drop by signature alone.
-- Drop every overload of the helpers to make this idempotent.
do $$
declare r record;
begin
  for r in
    select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('food_category', 'pick_for_preference',
                        'get_daily_recommendation')
  loop
    execute format('drop function if exists %I.%I(%s) cascade',
                  r.nspname, r.proname, r.args);
  end loop;
end $$;


-- ---------- 1. Classifier for a single food ID ----------
-- Returns one of: 'vegetarian', 'fish', 'beef', 'meat', 'other'.
-- Uses the existing tags text[] column; no schema change.
create or replace function public.food_category(p_id text)
returns text
language plpgsql
stable
as $$
declare
  has_veg   boolean;
  has_egg   boolean;
begin
  if p_id is null then return 'other'; end if;

  select ('vegetarian' = any(tags)), ('vegetarian_egg' = any(tags))
    into has_veg, has_egg
  from public.foods
  where id = p_id;

  if not found then return 'other'; end if;

  if has_veg or has_egg then return 'vegetarian'; end if;

  if p_id in ('p_rui','p_katla','p_hilsa','p_pabda','p_shing','p_tilapia',
              'p_ilish','p_koi','p_sola','p_mola','p_boal','p_ayre')
    then return 'fish';
  end if;

  if p_id in ('p_goru','p_beef') then return 'beef'; end if;

  if exists(select 1 from public.foods
            where id = p_id and category = 'protein')
    then return 'meat';
  end if;

  return 'other';
end;
$$;


-- ---------- 2. Pick the food ID that matches the user's preference ----------
-- Returns the primary if it satisfies the preference, otherwise the alt.
-- If neither does, returns the primary so the UI never shows an empty slot.
create or replace function public.pick_for_preference(
  p_primary_id text,
  p_alt_id     text,
  p_pref       text
) returns text
language plpgsql
stable
as $$
begin
  if p_pref is null or p_pref = 'omnivore' then
    return p_primary_id;
  end if;

  if p_pref = 'vegetarian' then
    if public.food_category(p_primary_id) in ('vegetarian','other')
      then return p_primary_id; end if;
    if p_alt_id is not null
       and public.food_category(p_alt_id) in ('vegetarian','other')
      then return p_alt_id; end if;
  elsif p_pref = 'fish_only' then
    if public.food_category(p_primary_id) in ('fish','vegetarian','other')
      then return p_primary_id; end if;
    if p_alt_id is not null
       and public.food_category(p_alt_id) in ('fish','vegetarian','other')
      then return p_alt_id; end if;
  elsif p_pref = 'no_beef' then
    if public.food_category(p_primary_id) <> 'beef'
      then return p_primary_id; end if;
    if p_alt_id is not null and public.food_category(p_alt_id) <> 'beef'
      then return p_alt_id; end if;
  end if;

  return p_primary_id;
end;
$$;


-- ---------- 3. Rewrite get_daily_recommendation ----------
-- Routes every protein/dal slot through pick_for_preference().
-- NOTE: breakfast_alt / morning_snack_alt / evening_snack_alt are
-- text[] in the schema, so we intentionally don't touch them here —
-- breakfast and snacks are usually vegetarian already, and indexing
-- text[] from a SELECT INTO row variable is the source of the
-- "cannot subscript type text" error.
create or replace function public.get_daily_recommendation(p_user_id uuid, p_day int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cls jsonb;
  plan_row public.meal_plan_days;
  pref text;
  result jsonb;
  p_lunch_carb     text;
  p_lunch_protein  text;
  p_lunch_veg      text;
  p_lunch_dal      text;
  p_dinner_carb    text;
  p_dinner_protein text;
  p_dinner_veg     text;
  p_breakfast      text;
  p_morning_snack  text;
  p_evening_snack  text;
begin
  cls := public.classify_user(p_user_id);
  pref := coalesce(cls->>'food_preference', 'omnivore');

  select * into plan_row from public.meal_plan_days where day = p_day;
  if not found then
    raise exception 'No plan found for day %', p_day;
  end if;

  -- Apply the preference to every animal-protein slot.
  p_breakfast      := plan_row.breakfast_main;
  p_lunch_carb     := plan_row.lunch_carb;
  p_lunch_protein  := public.pick_for_preference(
                        plan_row.lunch_protein,
                        plan_row.lunch_protein_alt,
                        pref);
  p_lunch_veg      := plan_row.lunch_vegetable;
  p_lunch_dal      := public.pick_for_preference(
                        plan_row.lunch_dal,
                        null,
                        pref);
  p_dinner_carb    := plan_row.dinner_carb;
  p_dinner_protein := public.pick_for_preference(
                        plan_row.dinner_protein,
                        plan_row.dinner_protein_alt,
                        pref);
  p_dinner_veg     := plan_row.dinner_vegetable;
  p_morning_snack  := plan_row.morning_snack;
  p_evening_snack  := plan_row.evening_snack;

  result := jsonb_build_object(
    'day', p_day,
    'classification', cls,
    'breakfast', public.pick_food(cls, p_breakfast, null),
    'lunch', jsonb_build_object(
      'carb',      to_jsonb((select f from public.foods f where f.id = p_lunch_carb)),
      'protein',   public.pick_food(cls, p_lunch_protein, null),
      'vegetable', to_jsonb((select f from public.foods f where f.id = p_lunch_veg)),
      'dal',       public.pick_food(cls, p_lunch_dal, null)
    ),
    'dinner', jsonb_build_object(
      'carb',      to_jsonb((select f from public.foods f where f.id = p_dinner_carb)),
      'protein',   public.pick_food(cls, p_dinner_protein, null),
      'vegetable', to_jsonb((select f from public.foods f where f.id = p_dinner_veg))
    ),
    'morning_snack', to_jsonb((select f from public.foods f where f.id = p_morning_snack)),
    'evening_snack', to_jsonb((select f from public.foods f where f.id = p_evening_snack))
  );
  return result;
end;
$$;
