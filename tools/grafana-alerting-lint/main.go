package main

import (
	"encoding/json"
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
	if len(os.Args) != 3 {
		fmt.Fprintf(os.Stderr, "usage: %s templates.json contact-points.json\n", os.Args[0])
		os.Exit(2)
	}

	templates := mustLoadTemplates(os.Args[1])
	contactPoints := mustLoadContactPoints(os.Args[2])

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
