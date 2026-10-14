component extends="megaphone.models.BaseNotification" {

    function via( notifiable ) {
        return [ "emailDigest" ];
    }
    function toEmailDigest( notifiable ) {
        return getQueueProperties();
    }

}
