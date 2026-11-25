let
  # Grafana's default Telegram message dumps the firing value, every label and
  # the raw annotation list. Our rules already carry a tidy summary/description,
  # so render just those two lines plus the Source/Silence links. Email keeps
  # Grafana's own HTML template; only the Telegram receiver uses this.
  alertsTelegramTemplate = ''
    {{ define "alcachofa.alert" }}{{ if .Annotations.summary }}{{ .Annotations.summary }}{{ else if .Labels.alertname }}{{ .Labels.alertname }}{{ if .Labels.instance }} on {{ .Labels.instance }}{{ end }}{{ else if .Labels.instance }}Alert on {{ .Labels.instance }}{{ else }}Alert{{ end }}
    {{ if .Annotations.description }}
    {{ .Annotations.description }}
    {{ end }}{{ if gt (len .GeneratorURL) 0 }}Source: {{ .GeneratorURL }}
    {{ end }}{{ if gt (len .SilenceURL) 0 }}Silence: {{ .SilenceURL }}
    {{ end }}{{ end }}
    {{ define "alcachofa.message" }}{{ range .Alerts.Firing }}{{ template "alcachofa.alert" . }}
    {{ end }}{{ range .Alerts.Resolved }}✅ Resolved - {{ template "alcachofa.alert" . }}
    {{ end }}{{ end }}
  '';
in
{
  apiVersion = 1;
  templates = [
    {
      orgId = 1;
      name = "alcachofa-telegram";
      template = alertsTelegramTemplate;
    }
  ];
}
