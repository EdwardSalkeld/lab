{ builders, ... }:

let
  inherit (builders) mkOctopusFreshnessAlert;
in
[
  {
    orgId = 1;
    name = "Octopus Data Freshness";
    folder = "Ops";
    interval = "1h";
    rules = [
      (mkOctopusFreshnessAlert {
        uid = "octopus-electricity-data-stale";
        title = "Octopus electricity data stale";
        usageType = "electricity";
        panelId = 1;
      })
      (mkOctopusFreshnessAlert {
        uid = "octopus-gas-data-stale";
        title = "Octopus gas data stale";
        usageType = "gas";
        panelId = 2;
      })
    ];
  }
]
