-- ============================================================
-- Amar Diet — User-defined 30-day progressive workout plan
-- Apply AFTER 15_diabetes_12ex.sql (which provides the 12 curated
-- exercise ids) and 16_timer_cumulative_fix.sql (cumulative timer).
--
-- This migration REPLACES the 30-day plan seeded by 15_*.sql with a
-- 4-week progressive program authored by the user. The catalogue of
-- 12 exercises stays the same; we only rewrite the assignments so
-- each calendar day follows the user's progressive schedule.
--
-- Why a new file instead of editing 15_*.sql:
--   • 15_*.sql is the canonical "12 curated exercises" seed. Keeping
--     the catalogue edit there means a future re-run of 15_*.sql will
--     re-seed the 12 routines but NOT touch this plan.
--   • 17_*.sql is the plan layer. Re-running it is idempotent and
--     can be applied repeatedly without re-running the rest.
--
-- Schedule (days rotate against `program day`, NOT sign-up date):
--   Week 1 (D1..D7)  — Intro: walking + light stretching only
--   Week 2 (D8..D14) — Add chair squats
--   Week 3 (D15..D21)— Add brisk walking + resistance band + balance
--   Week 4 (D22..D30)— Progressive, multi-exercise days up to 2–3/day
--   REST pattern (D7, D14, D21, D28) — stretching only, no cardio
--
-- Total volume per day stays in the 18–35 minute range so the
-- elderly-friendly UX (large buttons, 17–19pt body) is preserved.
-- ============================================================

-- ---------- 1. CLEANUP OLD PLAN ----------
-- The cross-user reseed in 15_*.sql pushed a fixed 6-day rotation
-- to every existing user. We deactivate those rows so analytics stop
-- showing the old plan, then seed the new program per user below.
update public.workout_assignments
set is_active = false
where is_active;

-- ---------- 2. SEED NEW 30-DAY PLAN FOR EVERY USER ----------
-- One row per (user, day_index, workout_id, position). The pattern
-- builds a 4-week progressive cycle; REST days are stretching only.
-- `position` orders the cards in the today screen (0 = first).
insert into public.workout_assignments
  (user_id, day_index, workout_id, position, is_active)
select
  u.id as user_id,
  p.day_index,
  p.workout_id,
  p.position,
  true
from auth.users u
cross join (
  values
    -- ============================================================
    -- WEEK 1 — INTRO (D1..D7)
    -- Goal: build the habit. Walking + light stretching only.
    -- Approx. 18–22 min/day. D7 = REST (stretching only).
    -- ============================================================
    -- D1: walking + shoulder + neck (intro triple)
    (1, 'ex02_walking',    0),
    (1, 'ex09_shoulder',   1),
    (1, 'ex10_neck',       2),
    -- D2: walking + shoulder
    (2, 'ex02_walking',    0),
    (2, 'ex09_shoulder',   1),
    -- D3: walking + neck
    (3, 'ex02_walking',    0),
    (3, 'ex10_neck',       1),
    -- D4: walking + shoulder
    (4, 'ex02_walking',    0),
    (4, 'ex09_shoulder',   1),
    -- D5: walking + neck
    (5, 'ex02_walking',    0),
    (5, 'ex10_neck',       1),
    -- D6: walking + shoulder + neck (longer intro day)
    (6, 'ex02_walking',    0),
    (6, 'ex09_shoulder',   1),
    (6, 'ex10_neck',       2),
    -- D7: REST — stretching only
    (7, 'ex09_shoulder',   0),
    (7, 'ex10_neck',       1),

    -- ============================================================
    -- WEEK 2 — ADD CHAIR SQUATS (D8..D14)
    -- Goal: introduce lower-body strength. Still 18–24 min/day.
    -- Keeps walking daily so habit sticks.
    -- ============================================================
    -- D8: walking + shoulder + neck + chair squats
    (8, 'ex02_walking',    0),
    (8, 'ex09_shoulder',   1),
    (8, 'ex10_neck',       2),
    (8, 'ex06_chair_squats', 3),
    -- D9: walking + chair squats + neck
    (9, 'ex02_walking',    0),
    (9, 'ex06_chair_squats', 1),
    (9, 'ex10_neck',       2),
    -- D10: walking + shoulder + chair squats
    (10, 'ex02_walking',   0),
    (10, 'ex09_shoulder',  1),
    (10, 'ex06_chair_squats', 2),
    -- D11: walking + chair squats + neck
    (11, 'ex02_walking',   0),
    (11, 'ex06_chair_squats', 1),
    (11, 'ex10_neck',      2),
    -- D12: walking + shoulder + chair squats
    (12, 'ex02_walking',   0),
    (12, 'ex09_shoulder',  1),
    (12, 'ex06_chair_squats', 2),
    -- D13: walking + chair squats + neck
    (13, 'ex02_walking',   0),
    (13, 'ex06_chair_squats', 1),
    (13, 'ex10_neck',      2),
    -- D14: REST — stretching only
    (14, 'ex09_shoulder',  0),
    (14, 'ex10_neck',      1),

    -- ============================================================
    -- WEEK 3 — STEP IT UP (D15..D21)
    -- Goal: brisk walking 10 min replaces casual walking on cardio
    -- days; add resistance band + single-leg balance. ~24–28 min/day.
    -- ============================================================
    -- D15: brisk walking + chair squats + shoulder
    (15, 'ex04_brisk_walk', 0),
    (15, 'ex06_chair_squats', 1),
    (15, 'ex09_shoulder',   2),
    -- D16: walking + resistance band + neck
    (16, 'ex02_walking',    0),
    (16, 'ex01_band',       1),
    (16, 'ex10_neck',       2),
    -- D17: brisk walking + single-leg stand + shoulder
    (17, 'ex04_brisk_walk', 0),
    (17, 'ex03_single_leg', 1),
    (17, 'ex09_shoulder',   2),
    -- D18: walking + resistance band + neck
    (18, 'ex02_walking',    0),
    (18, 'ex01_band',       1),
    (18, 'ex10_neck',       2),
    -- D19: brisk walking + chair squats + single-leg stand
    (19, 'ex04_brisk_walk', 0),
    (19, 'ex06_chair_squats', 1),
    (19, 'ex03_single_leg', 2),
    -- D20: walking + resistance band + neck + shoulder
    (20, 'ex02_walking',    0),
    (20, 'ex01_band',       1),
    (20, 'ex10_neck',       2),
    (20, 'ex09_shoulder',   3),
    -- D21: REST
    (21, 'ex09_shoulder',   0),
    (21, 'ex10_neck',       1),

    -- ============================================================
    -- WEEK 4 — PROGRESSIVE / FULL WEEK (D22..D30)
    -- Goal: 2–3 exercises/day; brisk walking 20 min on cardio days.
    -- Total ~28–35 min/day. Users who trained through week 3 can
    -- sustain this volume; everyone else is encouraged to repeat
    -- Week 3 instead via the day navigator.
    -- ============================================================
    -- D22: brisk walking (20 min) + resistance band + neck
    (22, 'ex04_brisk_walk', 0),
    (22, 'ex01_band',       1),
    (22, 'ex10_neck',       2),
    -- D23: brisk walking + chair squats + single-leg stand + shoulder
    (23, 'ex04_brisk_walk', 0),
    (23, 'ex06_chair_squats', 1),
    (23, 'ex03_single_leg', 2),
    (23, 'ex09_shoulder',   3),
    -- D24: brisk walking + resistance band + neck
    (24, 'ex04_brisk_walk', 0),
    (24, 'ex01_band',       1),
    (24, 'ex10_neck',       2),
    -- D25: brisk walking + chair squats + wall push-ups + shoulder
    (25, 'ex04_brisk_walk', 0),
    (25, 'ex06_chair_squats', 1),
    (25, 'ex12_wall_pushup', 2),
    (25, 'ex09_shoulder',   3),
    -- D26: brisk walking + resistance band + neck + sit-to-stand
    (26, 'ex04_brisk_walk', 0),
    (26, 'ex01_band',       1),
    (26, 'ex10_neck',       2),
    (26, 'ex11_sit_to_stand', 3),
    -- D27: brisk walking + single-leg stand + wall push-ups + shoulder
    (27, 'ex04_brisk_walk', 0),
    (27, 'ex03_single_leg', 1),
    (27, 'ex12_wall_pushup', 2),
    (27, 'ex09_shoulder',   3),
    -- D28: REST
    (28, 'ex09_shoulder',   0),
    (28, 'ex10_neck',       1),
    -- D29: gentle finish — brisk walking + chair squats + neck
    (29, 'ex04_brisk_walk', 0),
    (29, 'ex06_chair_squats', 1),
    (29, 'ex10_neck',       2),
    -- D30: light finish — walking + shoulder + neck
    (30, 'ex02_walking',    0),
    (30, 'ex09_shoulder',   1),
    (30, 'ex10_neck',       2)
) as p(day_index, workout_id, position)
on conflict (user_id, day_index, workout_id) do update set
  position   = excluded.position,
  is_active  = true;

-- ---------- 3. SELF-HEAL FOR THE CURRENT USER ----------
-- The cross-join against `auth.users` is invisible from some RLS
-- contexts, so a brand-new account can be created with an empty
-- assignment grid. Mirror 15_*.sql's safety net: a callable RPC
-- that seeds the progressive plan for the calling user on demand.
create or replace function public.seed_my_progressive_plan()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    return;
  end if;

  -- Deactivate any old plan rows that conflict with the new pattern.
  update public.workout_assignments a
  set is_active = false
  where a.user_id = v_user
    and a.is_active
    and a.workout_id in (
      'ex02_walking','ex04_brisk_walk','ex09_shoulder','ex10_neck',
      'ex06_chair_squats','ex01_band','ex03_single_leg',
      'ex12_wall_pushup','ex11_sit_to_stand'
    );

  insert into public.workout_assignments
    (user_id, day_index, workout_id, position, is_active)
  values
    -- Week 1
    (v_user, 1,  'ex02_walking', 0, true),
    (v_user, 1,  'ex09_shoulder', 1, true),
    (v_user, 1,  'ex10_neck', 2, true),
    (v_user, 2,  'ex02_walking', 0, true),
    (v_user, 2,  'ex09_shoulder', 1, true),
    (v_user, 3,  'ex02_walking', 0, true),
    (v_user, 3,  'ex10_neck', 1, true),
    (v_user, 4,  'ex02_walking', 0, true),
    (v_user, 4,  'ex09_shoulder', 1, true),
    (v_user, 5,  'ex02_walking', 0, true),
    (v_user, 5,  'ex10_neck', 1, true),
    (v_user, 6,  'ex02_walking', 0, true),
    (v_user, 6,  'ex09_shoulder', 1, true),
    (v_user, 6,  'ex10_neck', 2, true),
    (v_user, 7,  'ex09_shoulder', 0, true),
    (v_user, 7,  'ex10_neck', 1, true),
    -- Week 2
    (v_user, 8,  'ex02_walking', 0, true),
    (v_user, 8,  'ex09_shoulder', 1, true),
    (v_user, 8,  'ex10_neck', 2, true),
    (v_user, 8,  'ex06_chair_squats', 3, true),
    (v_user, 9,  'ex02_walking', 0, true),
    (v_user, 9,  'ex06_chair_squats', 1, true),
    (v_user, 9,  'ex10_neck', 2, true),
    (v_user, 10, 'ex02_walking', 0, true),
    (v_user, 10, 'ex09_shoulder', 1, true),
    (v_user, 10, 'ex06_chair_squats', 2, true),
    (v_user, 11, 'ex02_walking', 0, true),
    (v_user, 11, 'ex06_chair_squats', 1, true),
    (v_user, 11, 'ex10_neck', 2, true),
    (v_user, 12, 'ex02_walking', 0, true),
    (v_user, 12, 'ex09_shoulder', 1, true),
    (v_user, 12, 'ex06_chair_squats', 2, true),
    (v_user, 13, 'ex02_walking', 0, true),
    (v_user, 13, 'ex06_chair_squats', 1, true),
    (v_user, 13, 'ex10_neck', 2, true),
    (v_user, 14, 'ex09_shoulder', 0, true),
    (v_user, 14, 'ex10_neck', 1, true),
    -- Week 3
    (v_user, 15, 'ex04_brisk_walk', 0, true),
    (v_user, 15, 'ex06_chair_squats', 1, true),
    (v_user, 15, 'ex09_shoulder', 2, true),
    (v_user, 16, 'ex02_walking', 0, true),
    (v_user, 16, 'ex01_band', 1, true),
    (v_user, 16, 'ex10_neck', 2, true),
    (v_user, 17, 'ex04_brisk_walk', 0, true),
    (v_user, 17, 'ex03_single_leg', 1, true),
    (v_user, 17, 'ex09_shoulder', 2, true),
    (v_user, 18, 'ex02_walking', 0, true),
    (v_user, 18, 'ex01_band', 1, true),
    (v_user, 18, 'ex10_neck', 2, true),
    (v_user, 19, 'ex04_brisk_walk', 0, true),
    (v_user, 19, 'ex06_chair_squats', 1, true),
    (v_user, 19, 'ex03_single_leg', 2, true),
    (v_user, 20, 'ex02_walking', 0, true),
    (v_user, 20, 'ex01_band', 1, true),
    (v_user, 20, 'ex10_neck', 2, true),
    (v_user, 20, 'ex09_shoulder', 3, true),
    (v_user, 21, 'ex09_shoulder', 0, true),
    (v_user, 21, 'ex10_neck', 1, true),
    -- Week 4
    (v_user, 22, 'ex04_brisk_walk', 0, true),
    (v_user, 22, 'ex01_band', 1, true),
    (v_user, 22, 'ex10_neck', 2, true),
    (v_user, 23, 'ex04_brisk_walk', 0, true),
    (v_user, 23, 'ex06_chair_squats', 1, true),
    (v_user, 23, 'ex03_single_leg', 2, true),
    (v_user, 23, 'ex09_shoulder', 3, true),
    (v_user, 24, 'ex04_brisk_walk', 0, true),
    (v_user, 24, 'ex01_band', 1, true),
    (v_user, 24, 'ex10_neck', 2, true),
    (v_user, 25, 'ex04_brisk_walk', 0, true),
    (v_user, 25, 'ex06_chair_squats', 1, true),
    (v_user, 25, 'ex12_wall_pushup', 2, true),
    (v_user, 25, 'ex09_shoulder', 3, true),
    (v_user, 26, 'ex04_brisk_walk', 0, true),
    (v_user, 26, 'ex01_band', 1, true),
    (v_user, 26, 'ex10_neck', 2, true),
    (v_user, 26, 'ex11_sit_to_stand', 3, true),
    (v_user, 27, 'ex04_brisk_walk', 0, true),
    (v_user, 27, 'ex03_single_leg', 1, true),
    (v_user, 27, 'ex12_wall_pushup', 2, true),
    (v_user, 27, 'ex09_shoulder', 3, true),
    (v_user, 28, 'ex09_shoulder', 0, true),
    (v_user, 28, 'ex10_neck', 1, true),
    (v_user, 29, 'ex04_brisk_walk', 0, true),
    (v_user, 29, 'ex06_chair_squats', 1, true),
    (v_user, 29, 'ex10_neck', 2, true),
    (v_user, 30, 'ex02_walking', 0, true),
    (v_user, 30, 'ex09_shoulder', 1, true),
    (v_user, 30, 'ex10_neck', 2, true)
  on conflict (user_id, day_index, workout_id) do update set
    position  = excluded.position,
    is_active = true;
end $$;

grant execute on function public.seed_my_progressive_plan() to authenticated;
