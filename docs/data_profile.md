# Raw data profile

Produced in P2 with the `profile-raw-data` skill: pandas over the files cached by `make fetch-raw`, Drive
snapshot fetched 2026-09-30. Nothing here has been modified. Cleaning decisions are at the bottom and are
filled in only once the human has decided.

## Files
| File | Bytes | sha256 (prefix) | Shape | What it really is |
|---|---|---|---|---|
| `bars.json` | 2,242 | `4670702bd78f0828` | array of 5 bars, each with a nested `stock` array (29 stock lines) | Bars + price list (**Bar**, **Stock** in the UML) |
| `beers.json` | 741 | `e03d117e879c12a7` | array of 8 | The **Beverage catalog** for all types (beer, tequila, whiskey), despite the file name |
| `visit_events.json` | 159,924 | `5550d5a135cbc053` | array of 1,000 flat events | Juan's visits and drinks (**Visit**, **Drink**) |

## Structure and types
| File.field | JSON type | Notes |
|---|---|---|
| bars.`barName` | string (5/5) | Unique. It is the join key used by events (`bar_name`). |
| bars.`address` | string (5/5) | Jerry's = "5 Park **Rd**, Gardens…" and Fat Cactus = "5 Park **Road**, Gardens…": the **same street address** written differently. |
| bars.`stock[].name` | string (29/29) | Beverage **name**, not barcode, is the reference. |
| bars.`stock[].price` | number (29/29) | 20.00 – 52.00. Currency is not stated (Cape Town addresses, so ZAR). The same beverage has a different price per bar. |
| beers.`name` | string | Unique (8 distinct). |
| beers.`codebar` | string | Has leading zeros (`0054384099`), so it **must stay text**. **Not unique:** Jose Cuervo and Don Julio share `24199034`. |
| beers.`type` | string | `beer` / `tequila` / `whiskey`, lowercase. |
| beers.`alcoholUnits` | number | beer 1.2, tequila 1.4, whiskey 1.4. |
| events.`uuid` | string (1000/1000) | Unique, a valid UUID per event. |
| events.`bar_name` | string (1000/1000) | All 5 bars appear. No orphans. |
| events.`drinks` | int (896) / null (104) | 1–5. Mean 2.64. Distribution: 1:192 · 2:254 · 3:239 · 4:107 · 5:104. |
| events.`beverage` | string (896) / null (104) | 9 distinct names. |
| events.`happy_hour` | bool (896) / null (104) | 470 true / 426 false. |
| events.`visited` | string `YYYY-MM-DD` (1000/1000) | **Date only, no time.** All parse. Range **2018-01-03 → 2019-09-22**, 509 distinct dates. |

`drinks`, `beverage` and `happy_hour` are **null together** in exactly the same 104 events and never
separately. These look like visits where nothing was drunk.

## Relationships
| Check | Result |
|---|---|
| Event bar → bars.json | 0 orphans. Every bar is visited. |
| Event beverage → catalog | **1 orphan name: `Tiger's Milk Lager` (84 events, 268 drinks).** No barcode, type or alcohol units. |
| Stock beverage → catalog | Same orphan (stocked only at Tiger's Milk). |
| Catalog → stock | Every catalog beverage is stocked somewhere. |
| Event (bar, beverage) → that bar's stock | **0 violations.** Every drink can be priced from `stock`. |
| Events per (bar, date) | 859 groups. 129 have more than one event (max 4). 28 groups mix a no-drink event with drink events. |
| Bars per date | 256 of 509 dates have events at more than one bar. |
| UML Visit → Bar `1..*` | The data never has more than one bar per event, so it is **N:1** in practice (see ERM). |

## Duplicates
- `uuid`: 0 duplicates.
- **7 pairs of events are identical on every field except `uuid`.** Their 0-based row positions are
  67/879, 85/119, 124/992, 303/671, 363/438, 669/774 and 855/859:

  | bar | date | beverage | drinks | HH |
  |---|---|---|---|---|
  | Cubana | 2019-06-30 | Castle Lite | 5 | no |
  | Cubana | 2019-02-01 | — | — | — |
  | Jerry's | 2018-03-31 | Castle Lite | 1 | yes |
  | Jerry's | 2018-07-06 | Castle Lite | 3 | no |
  | Tiger's Milk | 2018-02-26 | Red Label | 2 | yes |
  | Yours Truly | 2018-10-17 | Castle Lite | 2 | no |
  | Yours Truly | 2019-01-06 | — | — | — |
- Catalog: 0 duplicate names, 1 duplicate barcode (see above). Stock: 0 duplicate (bar, beverage) pairs.

## Anomalies and things validated (not "fixed")
- **"Black Label" typed `beer` with 1.2 units.** At first glance this looks like Johnnie Walker Black Label
  whiskey, but the bars are in Cape Town, where **Carling Black Label** is one of the best-selling beers. The
  catalog is consistent with that (beer units, beer-level price of 35). **Kept as beer.**
- `beers.json` holds all beverage types, so it's modeled as `beverage` with a type, not `beer`.
- The UML's `visitedOn: DateTime` is only a date in the data. Several events can share a (bar, date) and
  can't be ordered within a day.

## Sensitivity checks (why the open questions matter)
Units per event are drinks × alcohol units. The largest single event is 6.0 units, so **no single event
ever reaches 14 units**. "Drunk" only happens if units are summed across a day.

| Assumption on Tiger's Milk Lager units | Days ≥14 units (all time) | Days ≥14 in Sep-2019 (data month-to-date) | Days ≥14 in Aug-2019 (last full month) | Days ≥14 in last 30 days of data | Weeks >14 units (NHS; ISO Monday-start weeks, first week partial) |
|---|---|---|---|---|---|
| Unknown → excluded (0) | 12 | 0 | 0 | 0 | 83 / 90 |
| Same as other beers (1.2) | 18 | 0 | 1 | 1 | 87 / 90 |

**Q2 is on a knife-edge.** Found by the data-reviewer subagent:

| Counting rule | 1st | 2nd |
|---|---|---|
| All visits (D-006, **chosen**) | Yours Truly 207 | Jerry's 206 |
| All visits, 7 duplicate pairs dropped (rejected D-007 alternative) | Yours Truly 205 | Jerry's 204 |
| (bar, date) visits (rejected D-006 alternative) | Yours Truly 181 | Jerry's 177 |
| Only visits that included a drink | **Jerry's 191** | Tiger's Milk 184 (Yours Truly 178) |

So the Q2 SQL must count from `core.visit` with **no join to `drink`**, and must return a ranked list, not `limit 1`.

**NHS weeks are convention-sensitive.** With Sunday-start weeks the counts are 87/91 (lager excluded) and
88/91 (lager included). The verdict doesn't change (mean ≈ 33 units/week vs the 14 limit).

Q1 by type (drinks): beer 1,327 (+268 Tiger's Milk Lager if it's a beer) · tequila 513 · whiskey 257. The
winner doesn't change.

## Open questions for the human
1. **What is a Visit?** (a) each event (`uuid`) is one visit with at most one drink line; or (b) a visit is
   (bar, date) and events are drink lines within it. The 28 (bar, date) groups that mix no-drink and drink
   events favour (a). Affects Q2, Q4, and the Visit/Drink tables.
2. **The 7 identical-except-uuid pairs:** keep them as genuine repeat events (the uuids are distinct and
   same-day repeats are common), or treat them as duplicate records and drop one of each pair?
3. **Tiger's Milk Lager:** add it to the beverage catalog as `beer` with 1.2 units (documented assumption,
   no barcode), or keep it without units and exclude it from unit-based answers? This changes Q5.
4. **Shared barcode 24199034 (Jose Cuervo / Don Julio):** barcode can't be a unique key. Use a surrogate
   `beverage_id` and store the barcode as a non-unique attribute (with a flag test)?
5. **Same address for Jerry's and Fat Cactus:** treat them as two bars that share a building (no change),
   or report it as a likely data error?
6. **"Last month" (Q5):** the data ends 2019-09-22. Options: Sep-2019 month-to-date / Aug-2019 (last
   complete month) / the rolling 30 days to 2019-09-22.
7. **"Drunk" grain (Q5):** per calendar day (sum of units across all visits that day). Per visit never
   reaches 14.
8. **NHS weekly test (Q6):** the week definition (ISO Monday-start or Sunday-start), what to do with the
   partial first week, and whether to count "weeks over 14" or compare "average units per week" to 14.

## Cleaning decisions
Decided by the human on 2026-09-30. Implemented in dbt `staging`/seeds, never in raw.

| # | Decision | Implementation | Effect |
|---|---|---|---|
| C1 | **Each event is one visit** (`uuid` = visit id). A visit has 0..1 drink line in this data. The model allows many lines, unique per (stock item, happy hour). | `stg_visit_events` → `core.visit` (1,000 rows) + `core.drink` (896 rows) | Q4 = no-drink visits. The (bar, date) alternative is reported as a sensitivity note. |
| C2 | **Keep the 7 identical-except-uuid pairs** as genuine events. | No dedup. A warn-level dbt test `visit_events_identical_except_uuid` reports them. | Stays visible without changing the counts. |
| C3 | **Add Tiger's Milk Lager to the catalog as a beer, 1.2 units, no barcode**, flagged as an assumption. | dbt seed `beverage_catalog_supplement.csv` with `is_assumed = true` | Its 268 drinks count as beer and in the unit-based answers. |
| C4 | **Surrogate keys.** Barcode is a non-unique attribute. Shared addresses are kept. | `beverage_id`/`bar_id` from `generate_surrogate_key(name)`. Warn-level tests flag the barcode collision and the shared address (compared after normalising "Road"→"Rd" and case). | No silent changes to the source values. |
| C5 | Visit date is stored as `date` (`visited_on`). The UML's DateTime can't be honoured because the source has no time. | `core.visit.visited_on date` | Intra-day ordering is impossible. Documented as a limitation. |
| C6 | "Black Label" is kept as beer (Carling Black Label). | none | — |
| C7 | The source has no drinker attribute. All data is about Juan (per the brief). | dbt seed `drinker.csv` with one row (`Juan`). Every visit gets his `drinker_id`. | Implements D-012. |
