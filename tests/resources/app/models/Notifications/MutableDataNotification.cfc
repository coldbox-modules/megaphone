component extends="megaphone.models.BaseNotification" accessors="true" {

    property name="payload";
    property name="notificationService" inject="NotificationService@megaphone";

    /** Returns the database channel for this notification. */
    public array function via( required any notifiable ) {
        return [ "database" ];
    }

    /** Mutates nested data so recipient copies can be checked for isolation. */
    public struct function toDatabase( required any notifiable ) {
        variables.notificationService.getChannel( "database" );
        variables.payload.history.append( arguments.notifiable.getNotifiableId() );
        return variables.payload;
    }

}
