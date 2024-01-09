component extends="megaphone.models.BaseNotification" accessors="true" {

    property name="message";

    public array function via( notifiable ) {
        return [ "database" ];
    }

    public struct function toDatabase( notifiable ) {
        return { "message": getMessage() };
    }

}
