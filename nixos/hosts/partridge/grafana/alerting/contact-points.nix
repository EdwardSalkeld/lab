{ common }:

let
  inherit (common) alertsContactPointName backupEventsContactPointName alertsTelegramChatId;
in
{
  apiVersion = 1;
  contactPoints =
    let
      standard = {
        orgId = 1;
        name = alertsContactPointName;
        receivers = [
          {
            uid = "benye0c2pvif4a";
            name = "Email Alcachofa";
            type = "email";
            disableResolveMessage = false;
            settings = {
              addresses = "edsalkeld@fastmail.com";
              singleEmail = false;
            };
          }
          {
            uid = "telegram-alerts";
            name = "Telegram Alerts";
            type = "telegram";
            disableResolveMessage = false;
            settings = {
              bottoken = "$GRAFANA_TELEGRAM_BOT_TOKEN";
              chatid = alertsTelegramChatId;
              uploadImage = false;
              message = ''{{ template "alcachofa.message" . }}'';
              parse_mode = "None";
              disable_web_page_preview = true;
            };
          }
        ];
      };
    in
    [
      standard
      {
        orgId = 1;
        name = backupEventsContactPointName;
        # Event expiry is not a recovery; send only the firing notification.
        receivers = builtins.map (
          receiver:
          receiver
          // {
            uid = "${receiver.uid}-backup-events";
            disableResolveMessage = true;
          }
        ) standard.receivers;
      }
    ];
}
