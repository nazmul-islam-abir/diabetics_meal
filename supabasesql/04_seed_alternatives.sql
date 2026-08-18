-- ============================================================
-- Amar Diet — seed: food_alternatives
-- Every food has at least one Bangladesh-friendly low-cost alternative.
-- ============================================================
insert into public.food_alternatives (food_id, alternative_id, priority) values
-- oats -> ruti (the user's stated concern)
('b_oats_khichuri', 'b_lal_ruti', 1),
('b_oats_khichuri', 'b_sobji_ruti', 2),
('b_alt_oats_plain', 'b_lal_ruti', 1),
('b_alt_oats_plain', 'b_alt_lalchal_ruti', 2),
-- muri (high GI) -> chira-doi or cha-pata
('b_alt_muri', 'b_chira_doi', 1),
('b_alt_muri', 'b_cha_pata', 2),
('s_muri_chola', 's_chira', 1),
('s_muri_chola', 's_doi', 2),
('s_muri_chola', 's_badam', 3),
-- carby snacks -> fruit
('s_chira', 's_papaya', 1),
('s_chira', 's_dalim', 2),
('c_uguni', 'c_kumra', 1),
('c_uguni', 'c_lal_ruti_2', 2),
-- rice -> ruti swap (lower GI)
('c_lalchal_bhat', 'c_lal_ruti_3', 1),
('c_lalchal_bhat', 'c_lal_ruti_2', 2),
-- potatoes -> ruti or squash
('c_potato_1pc', 'c_lal_ruti_2', 1),
('c_potato_1pc', 'c_kumra', 2),
-- expensive fish -> local fish
('p_katla', 'p_rui', 1),
('p_katla', 'p_tilapia', 2),
('p_katla', 'p_shing', 3),
('p_deshi_murgi', 'p_murgi', 1),
('p_deshi_murgi', 'p_dim', 2),
('p_sola', 'p_dim', 1),
('p_sola', 'p_moshur_dal', 2),
-- imported fruits -> local fruits
('s_apple', 's_peyara', 1),
('s_apple', 's_papaya', 2),
('s_apple', 's_jambura', 3),
('s_am', 's_peyara', 1),
('s_am', 's_dalim', 2),
('s_kola', 's_papaya', 1),
('s_kola', 's_dalim', 2),
('s_am', 's_jambura', 3),
-- imported veg -> local veg
('v_bandhakopi', 'v_lau', 1),
('v_bandhakopi', 'v_dhundul', 2)
on conflict (food_id, alternative_id) do nothing;