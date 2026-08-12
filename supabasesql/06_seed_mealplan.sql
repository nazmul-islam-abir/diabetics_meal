-- ============================================================
-- Amar Diet — 30-day meal plan (low-cost, BD-friendly)
-- Cycle repeats every 10 days so the user gets familiar meals with small
-- rotations. All food ids reference 03_seed_foods.sql.
-- Apply AFTER 04_seed_alternatives.sql and 05_meal_intake_actions.sql.
-- ============================================================

insert into public.meal_plan_days (day, breakfast_main, breakfast_alt, lunch_carb, lunch_protein, lunch_protein_alt, lunch_vegetable, lunch_dal, dinner_carb, dinner_protein, dinner_protein_alt, dinner_vegetable, morning_snack, morning_snack_alt, evening_snack, evening_snack_alt) values
-- DAY 1
(1, 'b_lal_ruti',           ARRAY['b_sobji_ruti','b_alt_lalchal_ruti']::text[], 'c_lalchal_bhat', 'p_rui',         'p_tilapia', 'v_lau',     'd_moshur', 'c_lal_ruti_2', 'p_dim',           'p_moshur_dal', 'v_dhundul',  's_papaya',   's_sobji_sidho', 's_doi',        's_jambura'),
-- DAY 2 (oats → ruti swap baked in)
(2, 'b_alt_lalchal_ruti',   ARRAY['b_lal_ruti','b_sobji_ruti']::text[],         'c_lal_ruti_3',   'p_tilapia',     'p_pabda',    'v_begun',   'd_mug',     'c_lal_ruti_2', 'p_murgi',         'p_dim',       'v_lal_shak', 's_apple',     's_papaya',     's_chira',      's_dalim'),
-- DAY 3
(3, 'b_chira_doi',          ARRAY['b_cha_pata']::text[],                       'c_lalchal_bhat', 'p_moshur_dal', 'p_mug_dal', 'v_potol',  'd_moshur', 'c_lal_ruti_2', 'p_shing',         'p_rui',       'v_lal_shak',    's_papaya', 's_khichuri_light','s_peyara',  's_doi'),
-- DAY 4
(4, 'b_sobji_ruti',         ARRAY['b_lal_ruti']::text[],                       'c_lal_ruti_3',   'p_pabda',      'p_tilapia',  'v_korola', 'd_rola',    'c_lalchal_bhat', 'p_murgi',     'p_dim',       'v_borboti',    's_jambura', 's_dalim',      's_doi',         's_tetul'),
-- DAY 5
(5, 'b_cha_pata',           ARRAY['b_lal_ruti','b_chira_doi']::text[],         'c_lal_ruti_3',   'p_dim',        'p_moshur_dal','v_begun',  'd_moshur', 'c_lal_ruti_2', 'p_shing',         'p_tilapia',   'v_lau',        's_papaya', 's_sobji_sidho', 's_badam',       's_khichuri_light'),
-- DAY 6
(6, 'b_lal_ruti',           ARRAY['b_sobji_ruti']::text[],                     'c_lalchal_bhat', 'p_rui',        'p_katla',    'v_dhundul','d_mug',     'c_lal_ruti_2', 'p_moshur_dal',    'p_dim',       'v_potol',      's_dalim', 's_peyara',     's_doi',         's_jambura'),
-- DAY 7 (use kumra squash instead of potato for CKD users)
(7, 'b_alt_lalchal_ruti',   ARRAY['b_lal_ruti']::text[],                       'c_kumra',        'p_tilapia',    'p_pabda',    'v_borboti','d_moshur', 'c_lal_ruti_2', 'p_sola',          'p_dim',       'v_lal_shak',   's_papaya', 's_jambura',    's_khichuri_light','s_badam'),
-- DAY 8
(8, 'b_sobji_ruti',         ARRAY['b_alt_lalchal_ruti']::text[],               'c_lal_ruti_3',   'p_murgi',      'p_dim',       'v_lau',   'd_moshur', 'c_lalchal_bhat', 'p_moshur_dal','p_kosha_chickpea','v_kolmi', 's_peyara', 's_dalim',         's_doi',         's_sobji_sidho'),
-- DAY 9
(9, 'b_chira_doi',          ARRAY['b_cha_pata','b_lal_ruti']::text[],          'c_lalchal_bhat', 'p_shing',      'p_tilapia',  'v_begun', 'd_rola',    'c_lal_ruti_2', 'p_dim',           'p_moshur_dal','v_dhundul',    's_papaya', 's_jambura',    's_cha_biskut',  's_tetul'),
-- DAY 10
(10, 'b_lal_ruti',          ARRAY['b_alt_lalchal_ruti','b_sobji_ruti']::text[],'c_lal_ruti_3',   'p_mug_dal',    'p_dim',       'v_potol', 'd_moshur', 'c_lal_ruti_2', 'p_pabda',         'p_rui',       'v_lau',        's_dalim', 's_peyara',     's_khichuri_light','s_doi'),
-- DAY 11-20: repeat with vegetable/carb swaps for variety
(11, 'b_alt_lalchal_ruti',  ARRAY['b_lal_ruti']::text[],                       'c_lalchal_bhat', 'p_rui',        'p_shing',     'v_chichinga','d_mug',  'c_lal_ruti_3', 'p_murgi',        'p_dim',     'v_potol',        's_papaya', 's_jambura',     's_badam',     's_tetul'),
(12, 'b_sobji_ruti',        ARRAY['b_chira_doi']::text[],                      'c_lal_ruti_3',   'p_tilapia',    'p_dim',        'v_begun', 'd_moshur', 'c_lal_ruti_2', 'p_moshur_dal',  'p_kosha_chickpea','v_lal_shak', 's_dalim', 's_peyara',     's_doi',     's_khichuri_light'),
(13, 'b_lal_ruti',          ARRAY['b_cha_pata']::text[],                       'c_lalchal_bhat', 'p_pabda',      'p_murgi',      'v_korola','d_rola',    'c_lal_ruti_2', 'p_shing',         'p_rui',     'v_dhundul',      's_papaya', 's_dalim',       's_doi',     's_sobji_sidho'),
(14, 'b_chira_doi',         ARRAY['b_lal_ruti','b_alt_lalchal_ruti']::text[],  'c_lal_ruti_3',   'p_dim',        'p_moshur_dal', 'v_borboti','d_moshur', 'c_lalchal_bhat', 'p_tilapia',   'p_pabda',    'v_lau',          's_peyara', 's_jambura',     's_badam',   's_khichuri_light'),
(15, 'b_alt_lalchal_ruti',  ARRAY['b_sobji_ruti']::text[],                     'c_kumra',        'p_rui',        'p_tilapia',    'v_lau',  'd_mug',     'c_lal_ruti_2', 'p_moshur_dal',  'p_mug_dal',  'v_potol',        's_papaya', 's_dalim',       's_doi',     's_cha_biskut'),
(16, 'b_sobji_ruti',        ARRAY['b_lal_ruti']::text[],                       'c_lal_ruti_3',   'p_shing',      'p_pabda',      'v_begun','d_moshur', 'c_lal_ruti_2', 'p_murgi',         'p_dim',     'v_lal_shak',     's_dalim', 's_peyara',      's_badam',   's_khichuri_light'),
(17, 'b_cha_pata',          ARRAY['b_chira_doi']::text[],                      'c_lalchal_bhat', 'p_kosha_chickpea','p_moshur_dal','v_kolmi','d_moshur','c_lal_ruti_3', 'p_pabda',        'p_rui',     'v_chichinga',    's_papaya', 's_jambura',     's_doi',     's_tetul'),
(18, 'b_lal_ruti',          ARRAY['b_alt_lalchal_ruti']::text[],               'c_lal_ruti_3',   'p_tilapia',    'p_shing',      'v_potol','d_mug',     'c_lalchal_bhat', 'p_dim',        'p_moshur_dal','v_lau',          's_peyara', 's_dalim',       's_badam',   's_khichuri_light'),
(19, 'b_chira_doi',         ARRAY['b_lal_ruti']::text[],                       'c_lalchal_bhat', 'p_dim',        'p_murgi',      'v_begun','d_moshur', 'c_lal_ruti_2', 'p_rui',           'p_tilapia', 'v_lal_shak',     's_papaya', 's_jambura',     's_doi',     's_sobji_sidho'),
(20, 'b_alt_lalchal_ruti',  ARRAY['b_lal_ruti','b_sobji_ruti']::text[],         'c_lal_ruti_3',   'p_moshur_dal', 'p_mug_dal',    'v_borboti','d_rola', 'c_lal_ruti_2', 'p_shing',         'p_rui',     'v_dhundul',      's_dalim', 's_peyara',      's_badam',   's_khichuri_light'),
-- DAY 21-30: third rotation, slightly different shak/protein order
(21, 'b_sobji_ruti',        ARRAY['b_lal_ruti']::text[],                       'c_lalchal_bhat', 'p_rui',        'p_tilapia',    'v_lau',  'd_moshur', 'c_lal_ruti_2', 'p_dim',           'p_kosha_chickpea','v_potol','s_papaya', 's_jambura',     's_doi',     's_tetul'),
(22, 'b_lal_ruti',          ARRAY['b_chira_doi']::text[],                      'c_lal_ruti_3',   'p_pabda',      'p_shing',      'v_begun','d_mug',     'c_lal_ruti_2', 'p_murgi',         'p_dim',     'v_lal_shak',     's_dalim', 's_peyara',      's_badam',   's_khichuri_light'),
(23, 'b_chira_doi',         ARRAY['b_cha_pata']::text[],                       'c_lalchal_bhat', 'p_moshur_dal', 'p_dim',        'v_korola','d_moshur', 'c_lal_ruti_3', 'p_tilapia',       'p_rui',     'v_borboti',      's_papaya', 's_dalim',       's_doi',     's_sobji_sidho'),
(24, 'b_alt_lalchal_ruti',  ARRAY['b_lal_ruti']::text[],                       'c_lal_ruti_3',   'p_shing',      'p_rui',        'v_lau',  'd_moshur', 'c_lal_ruti_2', 'p_moshur_dal',  'p_mug_dal',  'v_potol',        's_peyara', 's_jambura',     's_badam',   's_khichuri_light'),
(25, 'b_sobji_ruti',        ARRAY['b_alt_lalchal_ruti']::text[],               'c_lalchal_bhat', 'p_dim',        'p_pabda',      'v_begun','d_mug',     'c_lal_ruti_2', 'p_murgi',         'p_kosha_chickpea','v_lal_shak','s_dalim', 's_peyara',      's_doi',     's_cha_biskut'),
(26, 'b_lal_ruti',          ARRAY['b_sobji_ruti']::text[],                     'c_kumra',        'p_rui',        'p_tilapia',    'v_borboti','d_moshur', 'c_lal_ruti_3', 'p_shing',         'p_dim',     'v_dhundul',      's_papaya', 's_jambura',     's_badam',   's_khichuri_light'),
(27, 'b_chira_doi',         ARRAY['b_lal_ruti']::text[],                       'c_lal_ruti_3',   'p_murgi',      'p_dim',        'v_lau',  'd_moshur', 'c_lal_ruti_2', 'p_moshur_dal',  'p_pabda',    'v_potol',        's_dalim', 's_peyara',      's_doi',     's_tetul'),
(28, 'b_sobji_ruti',        ARRAY['b_lal_ruti']::text[],                       'c_lalchal_bhat', 'p_tilapia',    'p_rui',        'v_begun','d_mug',     'c_lal_ruti_2', 'p_dim',           'p_kosha_chickpea','v_lal_shak','s_papaya', 's_jambura',     's_badam',   's_khichuri_light'),
(29, 'b_alt_lalchal_ruti',  ARRAY['b_lal_ruti']::text[],                       'c_lal_ruti_3',   'p_shing',      'p_pabda',      'v_korola','d_moshur', 'c_lal_ruti_2', 'p_rui',           'p_moshur_dal','v_lau',       's_dalim', 's_peyara',      's_doi',     's_sobji_sidho'),
(30, 'b_lal_ruti',          ARRAY['b_chira_doi','b_sobji_ruti']::text[],       'c_lalchal_bhat', 'p_moshur_dal', 'p_dim',        'v_borboti','d_mug',   'c_lal_ruti_3', 'p_murgi',         'p_shing',   'v_dhundul',      's_papaya', 's_jambura',     's_badam',   's_khichuri_light')
on conflict (day) do nothing;
