package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func decode[T any](t *testing.T, raw string) T {
	t.Helper()
	var out T
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		t.Fatalf("decode fixture: %v", err)
	}
	return out
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func assertProblems(t *testing.T, got []string, want ...string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("got %d problems, want %d:\n%s", len(got), len(want), strings.Join(got, "\n"))
	}
	for i := range want {
		if !strings.Contains(got[i], want[i]) {
			t.Errorf("problem %d = %q, want it to mention %q", i, got[i], want[i])
		}
	}
}

var testDatasources = datasourceIndex{
	uids:  map[string]bool{"prom-uid": true, "loki-uid": true},
	names: map[string]bool{"prometheus": true, "loki": true},
}

func TestRuleDatasources(t *testing.T) {
	rules := decode[ruleSettings](t, `{"groups": [{"name": "G", "rules": [
		{"uid": "good", "data": [
			{"refId": "A", "datasourceUid": "prom-uid", "model": {"datasource": {"uid": "prom-uid"}}},
			{"refId": "B", "datasourceUid": "__expr__", "model": {"datasource": {"uid": "__expr__"}}}
		]},
		{"uid": "unknown-query-uid", "data": [
			{"refId": "A", "datasourceUid": "gone", "model": {"datasource": {"uid": "gone"}}}
		]},
		{"uid": "model-disagrees", "data": [
			{"refId": "A", "datasourceUid": "loki-uid", "model": {"datasource": {"uid": "stale"}}}
		]}
	]}]}`)

	assertProblems(t, checkRuleDatasources(rules, testDatasources),
		`rule "unknown-query-uid" (group "G") query A uses datasource "gone"`,
		`rule "model-disagrees" (group "G") query A uses datasource "stale"`,
	)
}

func TestRuleDashboardLinks(t *testing.T) {
	dashboards := []dashboard{{UID: "dash", Path: "dash.json", PanelIDs: map[int]bool{1: true, 7: true}}}
	rules := decode[ruleSettings](t, `{"groups": [{"name": "G", "rules": [
		{"uid": "no-link", "annotations": {"summary": "x"}},
		{"uid": "good", "annotations": {"__dashboardUid__": "dash", "__panelId__": "7"}},
		{"uid": "missing-dashboard", "annotations": {"__dashboardUid__": "other", "__panelId__": "1"}},
		{"uid": "missing-panel", "annotations": {"__dashboardUid__": "dash", "__panelId__": "2"}},
		{"uid": "half-link", "annotations": {"__dashboardUid__": "dash"}},
		{"uid": "bad-panel", "annotations": {"__dashboardUid__": "dash", "__panelId__": "one"}}
	]}]}`)

	assertProblems(t, checkRuleDashboardLinks(rules, dashboards),
		`rule "missing-dashboard" links to dashboard "other"`,
		`rule "missing-panel" links to panel 2`,
		`rule "half-link" sets only one of`,
		`rule "bad-panel" has non-numeric __panelId__ "one"`,
	)
}

func TestParseDashboardFindsNestedPanelsAndDatasources(t *testing.T) {
	d, err := parseDashboard("d.json", []byte(`{
		"uid": "d",
		"annotations": {"list": [{"datasource": {"type": "grafana", "uid": "-- Grafana --"}}]},
		"panels": [
			{"id": 1, "type": "timeseries", "datasource": {"uid": "prom-uid"},
			 "targets": [{"datasource": {"uid": "loki-uid"}}]},
			{"id": 2, "type": "row", "collapsed": true, "panels": [
				{"id": 3, "datasource": {"uid": "${datasource}"}},
				{"id": 4, "datasource": "prometheus"}
			]}
		],
		"templating": {"list": [{"name": "ds", "datasource": {"type": "prometheus"}}]}
	}`))
	if err != nil {
		t.Fatal(err)
	}
	if d.UID != "d" {
		t.Errorf("UID = %q", d.UID)
	}
	for _, id := range []int{1, 2, 3, 4} {
		if !d.PanelIDs[id] {
			t.Errorf("panel %d not found in %v", id, d.PanelIDs)
		}
	}
	if len(d.DatasourceRefs) != 5 {
		t.Errorf("found %d datasource refs, want 5: %+v", len(d.DatasourceRefs), d.DatasourceRefs)
	}
	assertProblems(t, checkDashboardDatasources([]dashboard{d}, testDatasources))
}

func TestDashboardDatasources(t *testing.T) {
	d, err := parseDashboard("d.json", []byte(`{"uid": "d", "panels": [
		{"id": 1, "datasource": {"uid": "prom-uid"}, "targets": [{"datasource": {"uid": "deleted-uid"}}]},
		{"id": 2, "datasource": "old-name"},
		{"id": 3, "datasource": "loki"}
	]}`))
	if err != nil {
		t.Fatal(err)
	}

	assertProblems(t, checkDashboardDatasources([]dashboard{d}, testDatasources),
		`at /panels/0/targets/0/datasource uses datasource "deleted-uid"`,
		`at /panels/1/datasource uses datasource "old-name"`,
	)
}

func TestLoadDashboardsWalksSubfolders(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "top.json"), `{"uid": "top", "panels": [{"id": 1}]}`)
	writeFile(t, filepath.Join(root, "nested", "deeper", "inner.json"), `{"uid": "inner", "panels": [{"id": 5}]}`)
	writeFile(t, filepath.Join(root, "nested", "notes.md"), `not a dashboard`)

	providers := decode[dashboardProviders](t, `{"providers": [{"name": "ops", "options": {"path": `+mustJSON(t, root)+`}}]}`)
	dashboards, err := loadDashboards(providers)
	if err != nil {
		t.Fatal(err)
	}
	uids := map[string]bool{}
	for _, d := range dashboards {
		uids[d.UID] = true
	}
	if len(dashboards) != 2 || !uids["top"] || !uids["inner"] {
		t.Fatalf("loaded %+v, want top and inner", dashboards)
	}

	rules := decode[ruleSettings](t, `{"groups": [{"name": "G", "rules": [
		{"uid": "nested-link", "annotations": {"__dashboardUid__": "inner", "__panelId__": "5"}}
	]}]}`)
	assertProblems(t, checkRuleDashboardLinks(rules, dashboards))
}

func TestLoadDashboardsReportsBadJSON(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "sub", "broken.json"), `{"uid": `)
	providers := decode[dashboardProviders](t, `{"providers": [{"name": "ops", "options": {"path": `+mustJSON(t, root)+`}}]}`)
	if _, err := loadDashboards(providers); err == nil || !strings.Contains(err.Error(), "broken.json") {
		t.Fatalf("err = %v, want a decode error naming broken.json", err)
	}
}

func TestDashboardUIDs(t *testing.T) {
	assertProblems(t, checkDashboardUIDs([]dashboard{
		{UID: "a", Path: "a.json"},
		{UID: "a", Path: "copy.json"},
		{Path: "none.json"},
	}),
		`dashboard uid "a" is used by both a.json and copy.json`,
		`dashboard none.json has no uid`,
	)
}

func mustJSON(t *testing.T, v any) string {
	t.Helper()
	raw, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}
