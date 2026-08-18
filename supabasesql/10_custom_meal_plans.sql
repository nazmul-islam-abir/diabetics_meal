-- ============================================================
-- 10 — User-defined meal plans (CRUD)
-- ============================================================
-- Safe to re-run. Only side effects: creates a new table
-- (user_meal_plans) and 5 new RPCs. Nothing existing is touched.
--
-- Why this exists:
-- The 30-day rotation in meal_plan_days is the *suggested* plan.
-- Many users follow a doctor-prescribed meal plan that doesn't
-- fit any rotation slot (e.g. "tiffin at 4pm", "before-bed warm
-- milk"). This script lets each user build their own per-day
-- plan with:
--   * any food from the master foods table OR free-text custom food
--   * any slot name (built-in: breakfast/morning_snack/lunch/
--     evening_snack/dinner, plus free-form: tiffin/snack/etc.)
--   * optional scheduled time
--   * optional notes / portion
--   * soft delete via is_active=false
--
-- The existing AI suggestions continue to work; user entries are
-- a parallel layer. The Flutter app will fetch both and merge.

-- ---------- 1. USER MEAL PLANS ----------
create table if not exists public.user_meal_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  -- effective_date is the calendar day this entry applies to.
  effective_date date not null default ((now() at time zone 'Asia/Dhaka')::date),
  -- slot is the meal category. Allowed built-in slots are kept
  -- for analytics consistency, but the column is free text so users
  -- can add their own (e.g. 'tiffin', 'pre_workout', 'before_bed').
  slot text not null check (slot in (
    'breakfast','morning_snack','lunch','evening_snack','dinner',
    'tiffin','late_night','pre_workout','post_workout','other'
  )),
  -- scheduled_time is the clock time the user wants to eat.
  scheduled_time time,
  -- food_id is set when the entry points to the master foods list.
  food_id text references public.foods(id) on delete set null,
  -- custom_food_name is set when the user typed a free-text food
  -- (e.g. "doctor's prescribed rice + egg"). Either food_id or
  -- custom_food_name (or both) must be non-null.
  custom_food_name text,
  -- portion_label lets the user override the default portion.
  portion_label text,
  -- notes are free-form user notes (doctor instructions, reminders).
  notes text,
  -- position is the display order within the same (date, slot) bucket.
  position int not null default 0,
  -- is_active implements soft delete; the Flutter app sets it false
  -- instead of issuing a hard DELETE so undo is trivial.
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists user_meal_plans_user_date
  on public.user_meal_plans (user_id, effective_date) where is_active;

create index if not exists user_meal_plans_user_slot
  on public.user_meal_plans (user_id, slot) where is_active;

-- Enforce "at least one of food_id / custom_food_name is non-null".
alter table public.user_meal_plans
  drop constraint if exists user_meal_plans_has_food;
alter table public.user_meal_plans
  add constraint user_meal_plans_has_food
  check (food_id is not null or (custom_food_name is not null and length(trim(custom_food_name)) > 0));

alter table public.user_meal_plans enable row level security;
drop policy if exists "Users manage their own meal plans" on public.user_meal_plans;
create policy "Users manage their own meal plans"
  on public.user_meal_plans for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ---------- 2. AUTO-TOUCH updated_at ----------
create or replace function public.touch_user_meal_plans_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_user_meal_plans_touch on public.user_meal_plans;
create trigger trg_user_meal_plans_touch
  before update on public.user_meal_plans
  for each row execute function public.touch_user_meal_plans_updated_at();


-- ---------- 3. CREATE a single user meal-plan entry ----------
create or replace function public.create_user_meal_plan(
  p_effective_date date,
  p_slot text,
  p_scheduled_time time default null,
  p_food_id text default null,
  p_custom_food_name text default null,
  p_portion_label text default null,
  p_notes text default null,
  p_position int default 0
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
  if p_food_id is null
     and (p_custom_food_name is null or length(trim(p_custom_food_name)) = 0) then
    raise exception 'Either food_id or custom_food_name must be provided';
  end if;

  insert into public.user_meal_plans
    (user_id, effective_date, slot, scheduled_time, food_id,
     custom_food_name, portion_label, notes, position, is_active)
  values
    (v_user, p_effective_date, p_slot, p_scheduled_time, p_food_id,
     nullif(trim(p_custom_food_name), ''), nullif(trim(p_portion_label), ''),
     nullif(trim(p_notes), ''), p_position, true)
  returning id into v_id;
  return v_id;
end;
$$;


-- ---------- 4. UPDATE an existing user meal-plan entry ----------
-- All fields are optional; only the non-null ones are updated.
create or replace function public.update_user_meal_plan(
  p_id uuid,
  p_effective_date date default null,
  p_slot text default null,
  p_scheduled_time time default null,
  p_clear_scheduled_time boolean default false,
  p_food_id text default null,
  p_clear_food_id boolean default false,
  p_custom_food_name text default null,
  p_portion_label text default null,
  p_notes text default null,
  p_position int default null,
  p_is_active boolean default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_owner uuid;
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  select user_id into v_owner from public.user_meal_plans where id = p_id;
  if v_owner is null then raise exception 'Plan entry not found'; end if;
  if v_owner <> v_user then raise exception 'Not authorized'; end if;

  update public.user_meal_plans
    set effective_date  = coalesce(p_effective_date, effective_date),
        slot            = coalesce(p_slot, slot),
        scheduled_time  = case when p_clear_scheduled_time then null
                               when p_scheduled_time is not null then p_scheduled_time
                               else scheduled_time end,
        food_id         = case when p_clear_food_id then null
                               when p_food_id is not null then p_food_id
                               else food_id end,
        custom_food_name = case when p_custom_food_name is not null
                                then nullif(trim(p_custom_food_name), '')
                                else custom_food_name end,
        portion_label   = case when p_portion_label is not null
                               then nullif(trim(p_portion_label), '')
                               else portion_label end,
        notes           = case when p_notes is not null
                               then nullif(trim(p_notes), '')
                               else notes end,
        position        = coalesce(p_position, position),
        is_active       = coalesce(p_is_active, is_active)
  where id = p_id and user_id = v_user;
end;
$$;


-- ---------- 5. SOFT DELETE (deactivate) a single entry ----------
create or replace function public.delete_user_meal_plan(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  update public.user_meal_plans set is_active = false
    where id = p_id and user_id = v_user;
end;
$$;


-- ---------- 6. REPLACE ALL ENTRIES FOR A SINGLE DATE ----------
-- Used by the Flutter app when the user picks "Reset to my plan"
-- or when they confirm a wholesale edit of a day's schedule.
-- Pass an empty jsonb array to clear everything for that date.
create or replace function public.replace_user_day_plan(
  p_effective_date date,
  p_entries jsonb
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_count int := 0;
  v_entry jsonb;
begin
  if v_user is null then raise exception 'Not authenticated'; end if;

  -- Soft-delete every active entry for this date.
  update public.user_meal_plans
    set is_active = false
  where user_id = v_user
    and effective_date = p_effective_date
    and is_active = true;

  -- Insert the new batch.
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' then
    return 0;
  end if;

  for v_entry in select * from jsonb_array_elements(p_entries)
  loop
    insert into public.user_meal_plans
      (user_id, effective_date, slot, scheduled_time, food_id,
       custom_food_name, portion_label, notes, position, is_active)
    values
      (v_user,
       p_effective_date,
       v_entry->>'slot',
       (v_entry->>'scheduled_time')::time,
       v_entry->>'food_id',
       nullif(trim(coalesce(v_entry->>'custom_food_name', '')), ''),
       nullif(trim(coalesce(v_entry->>'portion_label', '')), ''),
       nullif(trim(coalesce(v_entry->>'notes', '')), ''),
       coalesce((v_entry->>'position')::int, 0),
       true);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;


-- ---------- 7. LIST ENTRIES FOR A DATE RANGE ----------
-- Returns every active user entry in the window. Default is the
-- last 7 days which is what the Flutter "My plan" tab needs.
create or replace function public.list_user_meal_plans(
  p_from date default ((now() at time zone 'Asia/Dhaka')::date - 6),
  p_to   date default ((now() at time zone 'Asia/Dhaka')::date)
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(p) order by p.effective_date, p.scheduled_time, p.position)
    from (
      select p.id, p.effective_date, p.slot, p.scheduled_time,
             p.food_id, p.custom_food_name, p.portion_label,
             p.notes, p.position, p.is_active,
             p.created_at, p.updated_at,
             case when p.food_id is not null
                  then (select row_to_json(f) from public.foods f where f.id = p.food_id)
                  else null end as food
      from public.user_meal_plans p
      where p.user_id = v_user
        and p.is_active = true
        and p.effective_date between p_from and p_to
    ) p
  ), '[]'::jsonb);
end;
$$;


-- ---------- 8. LIST ENTRIES FOR A SINGLE DATE (lightweight) ----------
create or replace function public.get_user_day_plan(p_effective_date date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(p) order by p.slot, p.scheduled_time, p.position)
    from (
      select p.id, p.effective_date, p.slot, p.scheduled_time,
             p.food_id, p.custom_food_name, p.portion_label,
             p.notes, p.position, p.is_active,
             p.created_at, p.updated_at,
             case when p.food_id is not null
                  then (select row_to_json(f) from public.foods f where f.id = p.food_id)
                  else null end as food
      from public.user_meal_plans p
      where p.user_id = v_user
        and p.is_active = true
        and p.effective_date = p_effective_date
    ) p
  ), '[]'::jsonb);
end;
$$;


-- ---------- 9. LIST FOODS for the picker (search by name_bn) ----------
-- Used by the "Add meal" sheet so the user can pick from the master
-- list instead of typing free text. ILIKE so it works for partial
-- Bangla matches. Returns the same shape as the foods table.
create or replace function public.search_foods(p_query text, p_limit int default 20)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  return coalesce((
    select jsonb_agg(row_to_json(f) order by
                       case when f.name_bn = p_query then 0
                            when f.name_bn ilike p_query || '%' then 1
                            when f.name_bn ilike '%' || p_query || '%' then 2
                            else 3 end,
                       f.name_bn)
    from (
      select * from public.foods
      where p_query is null
         or p_query = ''
         or name_bn ilike '%' || p_query || '%'
         or id = p_query
      limit greatest(p_limit, 1)
    ) f
  ), '[]'::jsonb);
end;
$$;