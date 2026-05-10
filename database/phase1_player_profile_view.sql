-- Phase 1 — Single read model for “where does profile data live?”
-- Run after: public.users, profiles, player_profiles, age_categories, weight_categories exist
-- (typically after sprint_a_foundations.sql).

CREATE OR REPLACE VIEW public.v_player_profile AS
SELECT
    u.id AS user_id,
    u.full_name,
    u.email,
    u.phone,
    u.national_id,
    u.role,
    u.is_active,
    u.club_name,
    u.club_id,
    u.age_group AS users_age_group,
    u.rank AS belt_rank,
    u.player_category,
    u.profile_bio,
    COALESCE(p.avatar_url, u.profile_photo_url) AS avatar_url,
    ac.code AS age_category_code,
    ac.label_en AS age_category_label,
    wc.code AS weight_category_code,
    wc.label_en AS weight_category_label,
    pp.notes AS player_profile_notes
FROM public.users u
LEFT JOIN public.profiles p ON p.user_id = u.id
LEFT JOIN public.player_profiles pp ON pp.user_id = u.id
LEFT JOIN public.age_categories ac ON ac.id = pp.age_category_id
LEFT JOIN public.weight_categories wc ON wc.id = pp.weight_category_id;

COMMENT ON VIEW public.v_player_profile IS
'Phase 1 read model: identity in users; face photo profiles.avatar_url then users.profile_photo_url; '
'canonical competition age/weight via player_profiles FKs with users.age_group as fallback label.';

GRANT SELECT ON public.v_player_profile TO authenticated;
