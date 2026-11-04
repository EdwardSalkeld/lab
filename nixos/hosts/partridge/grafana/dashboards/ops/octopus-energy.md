# Comparing energy usage with the Octopus app

Both Octopus dashboards use Europe/London time. For a calendar period, select
midnight at its start and midnight **after** its final day. The end is excluded:
26 October–1 November 2026 means 26 October 00:00 to 2 November 00:00.

The top cards total every stored reading within that range. They do not discard
partial weeks, sample the series, interpolate missing readings or add standing
charges. “Missing half-hours” counts absent readings separately for electricity
and gas; missing readings reduce the totals. The count includes the extra hour
when the clocks go back. Actual zero readings count as present.

Electricity is stored in kWh. This household's gas readings are stored in m³.
Gas energy and costs use m³ × 1.02264 × **40 MJ/m³ assumed** ÷ 3.6 and are
labelled estimates. This is the same assumption used by the memory reporting
scripts. It is not an exact supplier calorific value; no value was fitted to an
app screenshot. Exact app/bill parity requires the supplier's conversion for
the period, along with the same underlying readings and time boundaries.

For 26 October–1 November, the stored gas volume is 28.986 m³. The estimate
is 329.36 kWh; Edward's app screenshot shows 328.53 kWh. Electricity rounds
to 74.13 kWh in both. Do not describe the gas estimate as an exact match.

The weekly charts retain their existing filter (seven days, each with at least
46 readings). They omit partial weeks at the edges of a selected range, so use
the top cards for a month or other arbitrary period. Costs remain indicative
at 28p/kWh electricity and 7p/kWh gas, excluding standing charges.

Source unit/conversion documentation:
- https://developer.oegb-kraken.energy/guides/rest/api-endpoints/
- https://octopus.energy/blog/statement-questions/
