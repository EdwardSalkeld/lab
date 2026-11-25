{ common }:

{
  apiVersion = 1;
  policies = [
    {
      orgId = 1;
      receiver = common.alertsContactPointName;
      group_by = [
        "grafana_folder"
        "alertname"
      ];
    }
  ];
}
