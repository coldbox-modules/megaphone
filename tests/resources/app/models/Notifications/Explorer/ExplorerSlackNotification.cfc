component extends="megaphone.models.BaseNotification" accessors="true" {

    property name="blockJSON";

    public array function via( notifiable ) {
        return [ "slack" ];
    }

    public struct function toSlack() {
        return getBlockJSON();
    }

}
