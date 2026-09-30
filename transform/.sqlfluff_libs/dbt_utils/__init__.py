"""Lint-time stand-ins for dbt_utils macros so sqlfluff (jinja templater) renders models offline."""


def generate_surrogate_key(field_list):
    return "md5(" + " || '-' || ".join(f"coalesce(cast({f} as text), '')" for f in field_list) + ")"


def date_spine(datepart, start_date, end_date):
    return (
        f"select generate_series({start_date}, {end_date}, interval '1 {datepart}')::date as date_{datepart}"
    )
