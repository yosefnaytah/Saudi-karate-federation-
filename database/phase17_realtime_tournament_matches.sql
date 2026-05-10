-- Phase 17 — Enable Realtime on tournament_matches for live bracket / match control sync.
-- Run in Supabase SQL Editor (once per project).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'tournament_matches'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_matches;
  END IF;
END $$;
