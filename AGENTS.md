# BenchPro project notes

## Demo data

- Every synthetic, sample, or demo staffing request inserted into Supabase must set `is_demo = true`.
- Also prefix its company name with `DEMO |` and use a reserved `example.com` email with the `benchpro-demo+` prefix.
- Genuine client requests must keep the default `is_demo = false`.
- Before production cleanup, remove demo records only with `where is_demo = true` (optionally also confirm the demo email prefix); never delete real requests as part of demo cleanup.

