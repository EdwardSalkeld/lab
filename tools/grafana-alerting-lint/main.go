package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"text/template"
)

type templateSettings struct {
	Templates []struct {
		Name     string `json:"name"`
		Template string `json:"template"`
	} `json:"templates"`
}

type contactPointSettings struct {
	ContactPoints []struct {
		Name      string `json:"name"`
		Receivers []struct {
			Name     string         `json:"name"`
			Type     string         `json:"type"`
			Settings map[string]any `json:"settings"`
		} `json:"receivers"`
	} `json:"contactPoints"`
}

func main() {
	templatesPath := flag.String("templates", "", "alerting templates provisioning JSON")
	contactPointsPath := flag.String("contact-points", "", "alerting contact points provisioning JSON")
	rulesPath := flag.String("rules", "", "alerting rules provisioning JSON")
	datasourcesPath := flag.String("datasources", "", "datasources provisioning JSON")
	dashboardsPath := flag.String("dashboards", "", "dashboard providers provisioning JSON")
	flag.Parse()
	if *templatesPath == "" || *contactPointsPath == "" || *rulesPath == "" || *datasourcesPath == "" || *dashboardsPath == "" || flag.NArg() != 0 {
		flag.Usage()
		os.Exit(2)
	}

	checkTemplates(mustLoadTemplates(*templatesPath), mustLoadContactPoints(*contactPointsPath))

	var rules ruleSettings
	mustLoadJSON(*rulesPath, &rules)
	var datasourceConfig datasourceSettings
	mustLoadJSON(*datasourcesPath, &datasourceConfig)
	var providers dashboardProviders
	mustLoadJSON(*dashboardsPath, &providers)
	dashboards, err := loadDashboards(providers)
	if err != nil {
		fail("load dashboards: %v", err)
	}

	datasources := indexDatasources(datasourceConfig)
	var problems []string
	problems = append(problems, checkRuleDatasources(rules, datasources)...)
	problems = append(problems, checkDashboardUIDs(dashboards)...)
	problems = append(problems, checkRuleDashboardLinks(rules, dashboards)...)
	problems = append(problems, checkDashboardDatasources(dashboards, datasources)...)
	if len(problems) > 0 {
		for _, problem := range problems {
			fmt.Fprintln(os.Stderr, problem)
		}
		os.Exit(1)
	}
}

func checkTemplates(templates templateSettings, contactPoints contactPointSettings) {
	root := template.New("grafana-alerting").Option("missingkey=zero")
	for _, entry := range templates.Templates {
		if _, err := root.Parse(entry.Template); err != nil {
			fail("template %q does not parse: %v", entry.Name, err)
		}
	}

	sampleAlert := map[string]any{
		"Annotations": map[string]any{
			"summary":     "test summary",
			"description": "test description",
		},
		"Labels": map[string]any{
			"alertname":  "TestAlert",
			"instance":   "partridge",
			"job":        "grafana",
			"mountpoint": "/",
			"name":       "grafana.service",
		},
		"GeneratorURL": "https://example.invalid/source",
		"SilenceURL":   "https://example.invalid/silence",
	}
	sampleMessageData := map[string]any{
		"Alerts": map[string]any{
			"Firing":   []any{sampleAlert},
			"Resolved": []any{sampleAlert},
		},
	}

	for _, contactPoint := range contactPoints.ContactPoints {
		for _, receiver := range contactPoint.Receivers {
			message, ok := receiver.Settings["message"].(string)
			if !ok || message == "" {
				continue
			}

			receiverTemplate, err := root.Clone()
			if err != nil {
				fail("clone template set for %q/%q: %v", contactPoint.Name, receiver.Name, err)
			}
			if _, err := receiverTemplate.Parse(`{{ define "__receiver_message__" }}` + message + `{{ end }}`); err != nil {
				fail("receiver message %q/%q does not parse: %v", contactPoint.Name, receiver.Name, err)
			}
			if err := receiverTemplate.ExecuteTemplate(io.Discard, "__receiver_message__", sampleMessageData); err != nil {
				fail("receiver message %q/%q does not execute: %v", contactPoint.Name, receiver.Name, err)
			}
		}
	}
}

func mustLoadTemplates(path string) templateSettings {
	var out templateSettings
	mustLoadJSON(path, &out)
	return out
}

func mustLoadContactPoints(path string) contactPointSettings {
	var out contactPointSettings
	mustLoadJSON(path, &out)
	return out
}

func mustLoadJSON(path string, dst any) {
	f, err := os.Open(path)
	if err != nil {
		fail("open %s: %v", path, err)
	}
	defer f.Close()

	if err := json.NewDecoder(f).Decode(dst); err != nil {
		fail("decode %s: %v", path, err)
	}
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
