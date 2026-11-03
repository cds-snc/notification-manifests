# SigNoz Dashboards Helm Chart

Manage SigNoz dashboards as code using Helm.

## Usage

### Option 1: Load from Files (Recommended)

1. **Export your dashboards from SigNoz UI**
   - Go to Dashboard → Settings → Export
   - Save the JSON file to `charts/signoz-importer/dashboards/` directory
   - Example: `charts/signoz-importer/dashboards/k8s-node-overview.json`

2. **Configure the values file**
   
   In `overrides/system/signoz-importer.yaml`:
   
   ```yaml
   dashboards:
     - name: k8s-node-overview
       file: k8s-node-overview.json
     - name: k8s-pod-overview
       file: k8s-pod-overview.json
   ```

### Option 2: Inline Data

If you prefer to keep the JSON in the values file:

```yaml
dashboards:
  - name: k8s-node-overview
    data: |
      {
        "title": "K8s Node Overview",
        ... dashboard JSON ...
      }
```

## Deployment

Deploy with Helmfile:

```bash
helmfile -e <environment> apply
```

## How it Works

1. Dashboard JSON files are stored in ConfigMaps
2. A Helm hook Job runs after install/upgrade
3. The Job waits for SigNoz to be ready
4. Dashboards are imported via the SigNoz v2 API
5. Job cleans up automatically after 5 minutes

## Notes

- The chart uses a post-install/post-upgrade hook, so dashboards are imported after SigNoz is deployed
- Failed dashboard imports don't fail the entire job (continues with remaining dashboards)
- Legacy dashboard exports are converted by SigNoz when created through the v2 API
- Existing dashboards are matched by title and left unchanged; v2 PUT requires a v2-format payload
- Old import jobs are automatically cleaned up
- Dashboard files in `dashboards/` directory are packaged with the chart

## Weekly API and Admin activity

The [Notify API and Admin Weekly Activity dashboard](dashboards/notify-weekly-activity.json)
uses traces and is included in the environment dashboard list. It compares API
and Admin side by side: weekly observed request counts, daily activity bars,
hourly activity bars, weekly Apdex scores, average response times, error rates,
week-over-week comparison tables, and daily reports (sixteen panels
total). All panels use `LAST_1_WEEK`, independently of
the global dashboard time picker. Change the panel time preference to
`GLOBAL_TIME` if you want to explore other date ranges.

Summary tiles occupy two rows, with API on the left and Admin on the right.
The first row shows requests and Apdex for each service; the second shows
average response time and error rate. All eight tiles have equal width.
Side-by-side comparison tables follow the summary tiles, then daily and hourly charts.
Two full-width daily reports follow the charts, API first and Admin second.

### Daily reports

The reports use the same rolling seven-day window as the other panels, grouped
by `America/Toronto` calendar date. A rolling week normally touches eight dates:
`Day 1` is the oldest and `Day 8` is today. The `Period (Toronto)` row gives the
actual date under each fixed column heading. Edge dates are marked partial;
an empty edge period (for example, today when the range ends at midnight) shows
`N/A`. Day lengths follow Toronto daylight-saving transitions.

Rows include Apdex, mean response time, throughput in requests per minute, error
rate, CPU, memory, and mean database-call duration. Summary values are calculated
over the entire window, not averaged from daily summaries. Throughput divides
observed request counts by the clipped reporting interval's actual elapsed
minutes, including partial days and 23-/25-hour local dates. Missing request
observations show `N/A`, not zero traffic.

CPU uses `k8s.pod.cpu.usage` in cores; memory uses
`k8s.pod.memory.working_set` in decimal MB. Both select the
`notification-canada-ca` namespace and pod names starting with `notify-api-` or
`notify-admin-` (including API spot pods). Samples are averaged within each
series/minute, summed across service pod series per minute, then averaged across
the observed minutes in the day or whole week. These are average total pod
resources, not New Relic process metrics or percentages of CPU limits.
Incomplete pod collection can understate totals; missing metrics show `N/A`.
The queries assume each SigNoz instance contains only its own environment.

`DB call avg` is mean duration of observed CLIENT spans (`kind = 3`) carrying
`db.system`, `db.system.name`, `db.statement`, or `db.query.text`. It includes all
such service spans, including database calls made by health checks. It is not
New Relic's database-time percentage and is not the database server's CPU usage.
The four inbound-request rows retain the existing health-check exclusions;
pod resources and database calls cannot reliably exclude health-check work.

### Week-over-week comparisons

Each service's table shows Requests, Apdex, Avg response, and Error rate with
`This week`, `Previous week`, and `Change` columns. "This week" is the rolling
last seven days; "Previous week" is the seven days immediately before that,
not Toronto calendar weeks. The SQL extends both the resource lookup and span
scan into the previous period and retains the same service, SERVER-kind, and
health-check exclusions as the summary panels.

Request counts and response-time changes are relative percentages:
`100 * (current - previous) / previous`. Apdex changes are absolute score
differences; error-rate changes are percentage-point differences (`pp`).
Positive values mean increased, not necessarily improved: higher Apdex is
better, while lower response time and error rate are better.

The Change column prefixes values with coloured indicators: 🟢 for improvement
(higher Apdex or lower response time/error rate), 🔴 for regression, and ⚪ for
request-volume changes, unchanged values, or `N/A`. Volume is neutral because
more or less traffic is not inherently better. Changes that round to zero at
the displayed precision are neutral. These are text indicators, not cell
background colours; they preserve the existing table layout and change units.

At least 14 days of retained traces and comparable sampling are required.
Periods with no observed requests show `N/A`, including their changes, rather
than treating missing telemetry as zero traffic. Percentage changes with a
zero baseline also show `N/A`. A zero error rate with observed requests is
valid and still supports a percentage-point comparison. Partial retention or
collection gaps cannot be detected by these queries and can bias the comparison.

Average response times use total observed SERVER-span duration divided by the
request count over the whole week, converted from nanoseconds to milliseconds.
They include failed requests and exclude `/_status`, matching the request-count
scope. They are not unweighted averages of hourly means. No requests returns
null, and sampling and retention affect the results.

Error rates are weekly failed-request counts divided by all observed requests,
multiplied by 100 and displayed as percentages. A request fails if `has_error`
is true or `response_status_code` is HTTP 5xx, matching Apdex; a request meeting
both conditions counts once. HTTP 4xx is not automatically an error unless
the span is marked as such. Health checks are excluded, and no requests returns
null rather than zero percent.

API bars are blue (`#3B82F6`); Admin bars are orange (`#F97316`). Each bar
panel sets `customLegendColors` keyed by its query legend. If you rename a
legend, update its color-map key too.

The queries use `count()` filtered to
`service.name = 'notification-api' AND kind = 2` for API and
`service.name = 'notification-admin' AND kind = 2` for Admin (SERVER spans), excluding
internal, database, and outbound client spans. They do not require the optional
`notify_api_requests_total` metric. Trace sampling, instrumentation, and retention
affect the counts: these represent observed inbound request spans, not guaranteed
total traffic. Missing values are left as gaps rather than replaced with zero;
a gap is not evidence of no traffic.

The six request-count panels also apply
`AND (http.route NOT EXISTS OR http.route != '/_status')` to exclude the
health-check route used by both services' Kubernetes probes
(`/_status?simple=true`; query parameters are not part of `http.route`).
Spans without `http.route` are retained, so missing route instrumentation does
not discard unrelated traffic. Health checks without that attribute will also
remain; verify `http.route` on an actual health-check span in Traces Explorer.
This only filters dashboard queries; it does not drop ingested spans.

### Weekly Apdex

The two Apdex number panels use provisional targets of **1 second for API** and
**500 milliseconds for Admin**. These are starting estimates, not agreed SLOs.
For target `T`, non-failed requests with duration `<= T` are satisfied, those
with duration `> T` and `<= 4T` are tolerating, and slower requests are frustrated.
Spans with `has_error` or an HTTP 5xx `response_status_code` are always frustrated,
regardless of duration. HTTP 4xx responses are not automatically frustrated
unless the span records an error.

The score is `(satisfied + 0.5 * tolerating) / total`, from 0 to 1. The panels
use ClickHouse SQL against the trace tables to aggregate the whole selected week
in one calculation, rather than averaging hourly scores with unequal traffic.
An empty denominator returns null, not a misleading perfect or zero score.
Both SQL queries use the same service, SERVER-kind, and health-route scope as
the request panels. A missing `http.route` map entry is an empty string in
ClickHouse and is retained. Trace sampling and retention also affect Apdex.

To tune a target, update its panel title and description and all three duration
constants in its SQL: two occurrences of `T` and one of `4T`, in nanoseconds.

This is a SigNoz-only alternative to a calendar heatmap, not an exact replica.
SigNoz's documented Heatmap panel (v0.146.0+) displays distributions over time,
not calendar-day activity. No Grafana installation is needed.

Daily bars use fixed 86,400-second buckets, not `America/Toronto` calendar days.
The first and last buckets can be partial. Displaying timestamps in Toronto
time does not change the bucket boundaries, particularly across daylight-saving
transitions (23- or 25-hour local days). Do not interpret these as exact local
daily totals.

To try it without a Helm deployment, import the JSON through SigNoz's dashboard
import UI. Otherwise, deploy the importer with the normal environment Helmfile
workflow. The importer creates the dashboard only if its title does not already
exist; it does not overwrite subsequent UI edits.

If you previously imported separate API or Admin dashboards (or the original
metric-based version), replace the API dashboard JSON using SigNoz's JSON editor
and save it to use the combined version in place. The combined dashboard retains
the API dashboard UUID. Alternatively, import it as a new dashboard. Existing
standalone dashboards are not automatically removed from SigNoz; delete any
unwanted copies through the UI. Re-running the Helm importer will not update an
existing dashboard with the same title. To check the data source,
run `count()` in Traces Explorer with the relevant filter above over the last hour; if it
returns no spans, inspect the service name and span kind of an actual inbound
API span before changing the filter.
