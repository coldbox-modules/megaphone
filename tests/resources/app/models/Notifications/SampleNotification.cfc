component extends="megaphone.models.BaseNotification" {

    public array function via( notifiable ) {
        return [ "database" ];
    }

    public struct function toDatabase( notifiable ) {
        return { "foo": "bar", "notifiable": notifiable.getNotifiableId() };
    }

}
