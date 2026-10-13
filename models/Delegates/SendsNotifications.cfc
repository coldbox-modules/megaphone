component {

    property name="notificationService" inject="NotificationService@megaphone";

    public NotificationPublication function queue(
        required any notification,
        struct properties = {},
        struct options = {},
        string connection,
        string queue
    ) {
        arguments.notifiables = $parent;
        return variables.notificationService.queue( argumentCollection = arguments );
    }

    public BaseNotification function notify( required any notification, struct properties = {} ) {
        return variables.notificationService.notify( $parent, arguments.notification, arguments.properties );
    }

}
