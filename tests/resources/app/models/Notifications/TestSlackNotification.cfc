component extends="megaphone.models.BaseNotification" accessors="true" {

    property name="callback";

    public array function via( notifiable ) {
        return [ "slack" ];
    }

    public struct function toSlack( notifiable, newSlackMessage ) {
        var message = newSlackMessage();
        if ( !isNull( variables.callback ) ) {
            variables.callback( message );
        }
        return message;
    }

}
