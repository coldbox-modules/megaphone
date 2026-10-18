component extends="megaphone.models.BaseNotification" {

    function via( notifiable ) {
        return variables.channels ?: [ "dailyAuditions" ];
    }

    function toDigest( notifiable ) {
        return { "itemKey": variables.itemKey, "occurredAt": variables.occurredAt, "data": variables.data };
    }

}
