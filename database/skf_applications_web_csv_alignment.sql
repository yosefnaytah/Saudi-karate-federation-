-- Align web signups (skf-staff-register.html) with CSV import template:
--   database/skf_applications_import_template.csv
-- Header order: id,email,full_name,phone,national_id,notes,requested_role,status,assigned_skf_id,auth_user_id,reviewed_at,reviewed_by,created_at
--
-- Web flow (trigger handle_skf_staff_signup_application): fills email, full_name, phone, national_id, notes,
--   requested_role, status=pending, auth_user_id. id and created_at use table defaults.
-- CSV flow: leave id empty for default UUID; set status=pending; omit auth_user_id until applicant exists, or paste UUID after Auth user is created.
-- Approval (.NET): matches rows by skf_applications.id; if auth_user_id is set, keeps password and updates public.users.

COMMENT ON TABLE public.skf_applications IS
    'SKF staff applications. Columns match skf_applications_import_template.csv. Web registration sets auth_user_id; optional notes maps to CSV notes column.';

COMMENT ON COLUMN public.skf_applications.email IS 'CSV: email';
COMMENT ON COLUMN public.skf_applications.full_name IS 'CSV: full_name';
COMMENT ON COLUMN public.skf_applications.phone IS 'CSV: phone';
COMMENT ON COLUMN public.skf_applications.national_id IS 'CSV: national_id';
COMMENT ON COLUMN public.skf_applications.notes IS 'CSV: notes (optional)';
COMMENT ON COLUMN public.skf_applications.requested_role IS 'CSV: requested_role — skf_admin or referees_plus only';
COMMENT ON COLUMN public.skf_applications.status IS 'CSV: status — pending | approved | rejected';
COMMENT ON COLUMN public.skf_applications.assigned_skf_id IS 'CSV: assigned_skf_id — set on approval';
COMMENT ON COLUMN public.skf_applications.auth_user_id IS 'CSV: auth_user_id — web signup sets this to link the row to Auth for approval';

CREATE INDEX IF NOT EXISTS idx_skf_applications_auth_user_id ON public.skf_applications (auth_user_id)
    WHERE auth_user_id IS NOT NULL;
