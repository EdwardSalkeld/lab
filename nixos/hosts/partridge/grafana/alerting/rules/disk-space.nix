{ builders, ... }:

let
  inherit (builders) mkDiskSpaceAlert;
in
[
  {
    orgId = 1;
    name = "Disk Space";
    folder = "Ops";
    interval = "5m";
    rules = [
      (mkDiskSpaceAlert {
        uid = "disk-space-low-warning";
        title = "Disk space low";
        severity = "warning";
        thresholdText = "10%";
        evaluator = {
          params = [
            0.05
            0.10
          ];
          type = "within_range";
        };
      })
      (mkDiskSpaceAlert {
        uid = "disk-space-low-critical";
        title = "Disk space critically low";
        severity = "critical";
        thresholdText = "5%";
        evaluator = {
          params = [ 0.05 ];
          type = "lt";
        };
      })
    ];
  }
]
