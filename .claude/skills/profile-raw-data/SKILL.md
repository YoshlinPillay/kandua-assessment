---
name: profile-raw-data
description: Profile the raw Juan-the-Drinker JSON files (or the dlt `raw` schema) before any modeling decision. Use when asked to explore, profile or validate raw data, or before writing/changing staging or core models.
---

# Profile raw data

Goal: replace assumptions with evidence. Every finding cites the query or code that produced it.

## Steps
1. **Get the files.** Run `make fetch-raw`, which downloads the Drive files into `data/raw/` (gitignored, immutable).
   Record each file's size, record count and sha256.
2. **Structure.** For each file, report the top-level type, the keys, the nesting depth and the JSON type per key.
   Report keys whose type varies across records (e.g. price as a string in some records and a number in others).
3. **Per-field profile.** Report the null/empty count, distinct count, min/max for numbers and dates, the top 5
   values, and anything odd: whitespace, casing variants, encodings, currency symbols, time zones.
4. **Keys and duplicates.**
   - Find the candidate natural key per entity and whether it is actually unique.
   - Count exact duplicates, and count same-key-different-attributes conflicts separately.
5. **Relationships.** For every reference between files (bar name/id, beverage barcode/name):
   - count the orphans in both directions
   - check the UML multiplicities against the data (e.g. does a visit ever reference >1 bar?)
6. **Business sanity.** Date range, visits per day, quantity distribution, price ranges per beverage type,
   happy-hour share, and alcohol units per beverage.
7. **Write `docs/data_profile.md`** with the sections: Files · Structure · Field profiles · Keys & duplicates ·
   Relationships · Anomalies · **Open questions for the human** · Cleaning decisions (left empty until the human decides).

## Rules
- Use pandas in a throwaway script under the session scratchpad, or SQL against `raw.*` after the dlt load.
  Don't commit profiling scratch code unless it becomes a test.
- Never "fix" data during profiling. Report it.
- Anything that changes an answer (duplicates, orphans, ambiguous types) goes under **Open questions**. The human
  decides.
