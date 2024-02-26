component extends="megaphone.models.BaseNotification" {

    public array function via( notifiable ) {
        return [ "CustomNotificationProvider" ];
    }

    public boolean function toCustom( notifiable ) {
        return true;
    }

}
