package main

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type ruleSettings struct {
	Groups []struct {
		Name  string `json:"name"`
		Rules []rule `json:"rules"`
	} `json:"groups"`
}

type rule struct {
	UID  string `json:"uid"`
	Data []struct {
		RefID         string `json:"refId"`
		DatasourceUID string `json:"datasourceUid"`
		Model         struct {
			Datasource *struct {
				UID string `json:"uid"`
			} `json:"datasource"`
		} `json:"model"`
	} `json:"data"`
	Annotations map[string]string `json:"annotations"`
}

type datasourceSettings struct {
	Datasources []struct {
		Name string `json:"name"`
		UID  string `json:"uid"`
	} `json:"datasources"`
}

type dashboardProviders struct {
	Providers []struct {
		Name    string `json:"name"`
		Options struct {
			Path string `json:"path"`
		} `json:"options"`
	} `json:"providers"`
}

type dashboard struct {
	UID            string
	Path           string
	PanelIDs       map[int]bool
	DatasourceRefs []datasourceRef
}

type datasourceRef struct {
	Where string
	UID   string
	Name  string
}

// Datasource references that Grafana resolves itself rather than through a
// provisioned datasource.
var builtinDatasources = map[string]bool{
	"__expr__":        true,
	"-- Grafana --":   true,
	"grafana":         true,
	"-- Mixed --":     true,
	"-- Dashboard --": true,
}

type datasourceIndex struct {
	uids  map[string]bool
	names map[string]bool
}

func indexDatasources(settings datasourceSettings) datasourceIndex {
	idx := datasourceIndex{uids: map[string]bool{}, names: map[string]bool{}}
	for _, ds := range settings.Datasources {
		idx.uids[ds.UID] = true
		idx.names[ds.Name] = true
	}
	return idx
}

func (idx datasourceIndex) resolves(ref datasourceRef) bool {
	value := ref.UID
	if value == "" {
		value = ref.Name
	}
	if value == "" || builtinDatasources[value] || strings.HasPrefix(value, "$") {
		return true
	}
	if ref.UID != "" {
		return idx.uids[ref.UID]
	}
	// Old dashboards refer to a datasource by name as a bare string.
	return idx.names[ref.Name] || idx.uids[ref.Name]
}

func checkRuleDatasources(rules ruleSettings, datasources datasourceIndex) []string {
	var problems []string
	for _, group := range rules.Groups {
		for _, r := range group.Rules {
			for _, query := range r.Data {
				uids := []string{query.DatasourceUID}
				if query.Model.Datasource != nil && query.Model.Datasource.UID != query.DatasourceUID {
					uids = append(uids, query.Model.Datasource.UID)
				}
				for _, uid := range uids {
					if !datasources.resolves(datasourceRef{UID: uid}) {
						problems = append(problems, fmt.Sprintf("rule %q (group %q) query %s uses datasource %q, which is not provisioned", r.UID, group.Name, query.RefID, uid))
					}
				}
			}
		}
	}
	return problems
}

func checkRuleDashboardLinks(rules ruleSettings, dashboards []dashboard) []string {
	byUID := map[string]dashboard{}
	for _, d := range dashboards {
		byUID[d.UID] = d
	}

	var problems []string
	for _, group := range rules.Groups {
		for _, r := range group.Rules {
			dashboardUID, hasDashboard := r.Annotations["__dashboardUid__"]
			panelID, hasPanel := r.Annotations["__panelId__"]
			if !hasDashboard && !hasPanel {
				continue
			}
			if hasDashboard != hasPanel {
				problems = append(problems, fmt.Sprintf("rule %q sets only one of __dashboardUid__ and __panelId__", r.UID))
				continue
			}
			d, ok := byUID[dashboardUID]
			if !ok {
				problems = append(problems, fmt.Sprintf("rule %q links to dashboard %q, which is not provisioned", r.UID, dashboardUID))
				continue
			}
			id, err := strconv.Atoi(panelID)
			if err != nil {
				problems = append(problems, fmt.Sprintf("rule %q has non-numeric __panelId__ %q", r.UID, panelID))
				continue
			}
			if !d.PanelIDs[id] {
				problems = append(problems, fmt.Sprintf("rule %q links to panel %d, which dashboard %q (%s) does not have", r.UID, id, dashboardUID, d.Path))
			}
		}
	}
	return problems
}

func checkDashboardDatasources(dashboards []dashboard, datasources datasourceIndex) []string {
	var problems []string
	for _, d := range dashboards {
		for _, ref := range d.DatasourceRefs {
			if !datasources.resolves(ref) {
				value := ref.UID
				if value == "" {
					value = ref.Name
				}
				problems = append(problems, fmt.Sprintf("dashboard %q (%s) at %s uses datasource %q, which is not provisioned", d.UID, d.Path, ref.Where, value))
			}
		}
	}
	return problems
}

func checkDashboardUIDs(dashboards []dashboard) []string {
	seen := map[string]string{}
	var problems []string
	for _, d := range dashboards {
		if d.UID == "" {
			problems = append(problems, fmt.Sprintf("dashboard %s has no uid", d.Path))
			continue
		}
		if other, ok := seen[d.UID]; ok {
			problems = append(problems, fmt.Sprintf("dashboard uid %q is used by both %s and %s", d.UID, other, d.Path))
			continue
		}
		seen[d.UID] = d.Path
	}
	return problems
}

func loadDashboards(providers dashboardProviders) ([]dashboard, error) {
	var dashboards []dashboard
	for _, provider := range providers.Providers {
		if provider.Options.Path == "" {
			return nil, fmt.Errorf("dashboard provider %q has no options.path", provider.Name)
		}
		err := filepath.WalkDir(provider.Options.Path, func(path string, entry fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if entry.IsDir() || filepath.Ext(path) != ".json" {
				return nil
			}
			raw, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			d, err := parseDashboard(path, raw)
			if err != nil {
				return err
			}
			dashboards = append(dashboards, d)
			return nil
		})
		if err != nil {
			return nil, fmt.Errorf("dashboard provider %q: %w", provider.Name, err)
		}
	}
	return dashboards, nil
}

func parseDashboard(path string, raw []byte) (dashboard, error) {
	var doc map[string]any
	if err := json.Unmarshal(raw, &doc); err != nil {
		return dashboard{}, fmt.Errorf("decode %s: %w", path, err)
	}
	d := dashboard{Path: path, PanelIDs: map[int]bool{}}
	d.UID, _ = doc["uid"].(string)
	collectPanelIDs(doc["panels"], d.PanelIDs)
	collectDatasourceRefs(doc, "", &d.DatasourceRefs)
	sort.Slice(d.DatasourceRefs, func(i, j int) bool { return d.DatasourceRefs[i].Where < d.DatasourceRefs[j].Where })
	return d, nil
}

// Collapsed rows hold their panels in a nested "panels" list.
func collectPanelIDs(panels any, ids map[int]bool) {
	list, _ := panels.([]any)
	for _, item := range list {
		panel, ok := item.(map[string]any)
		if !ok {
			continue
		}
		if id, ok := panel["id"].(float64); ok {
			ids[int(id)] = true
		}
		collectPanelIDs(panel["panels"], ids)
	}
}

func collectDatasourceRefs(value any, where string, refs *[]datasourceRef) {
	switch v := value.(type) {
	case map[string]any:
		for key, child := range v {
			childWhere := where + "/" + key
			if key == "datasource" {
				switch ds := child.(type) {
				case map[string]any:
					uid, _ := ds["uid"].(string)
					if uid != "" {
						*refs = append(*refs, datasourceRef{Where: childWhere, UID: uid})
					}
				case string:
					*refs = append(*refs, datasourceRef{Where: childWhere, Name: ds})
				}
			}
			collectDatasourceRefs(child, childWhere, refs)
		}
	case []any:
		for i, child := range v {
			collectDatasourceRefs(child, where+"/"+strconv.Itoa(i), refs)
		}
	}
}
