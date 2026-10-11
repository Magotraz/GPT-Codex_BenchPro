ALTER TABLE public.clients
  ADD COLUMN IF NOT EXISTS website text;

COMMENT ON COLUMN public.clients.website IS
  'Optional official website URL for a client organization.';

NOTIFY pgrst, 'reload schema';
