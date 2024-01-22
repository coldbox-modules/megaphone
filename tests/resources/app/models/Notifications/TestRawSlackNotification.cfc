component extends="megaphone.models.BaseNotification" accessors="true" {

    public array function via( notifiable ) {
        return [ "slack" ];
    }

    public struct function toSlack( notifiable, newSlackMessage ) {
        return {
            "blocks": [
                { "type": "header", "text": { "type": "plain_text", "text": "Budget Performance" } },
                {
                    "type": "section",
                    "text": { "type": "mrkdwn", "text": "A message *with some bold text* and _some italicized text_." }
                },
                { "type": "header", "text": { "type": "plain_text", "text": "Market Performance" } }
            ]
        };
    }

}
