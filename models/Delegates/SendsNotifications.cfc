component {

    property name="notificationService" inject="NotificationService@megaphone";

    public NotificationPublication function queue(
        required any notification,
        struct properties = {},
        struct options = {}
    ) {
        return variables.notificationService.queue(
            $parent,
            arguments.notification,
            arguments.properties,
            arguments.options
        );
    }

    public BaseNotification function notify( required any notification, struct properties = {} ) {
        return variables.notificationService.notify( $parent, arguments.notification, arguments.properties );
    }

}
