component {

    property name="notificationService" inject="NotificationService@megaphone";

    /**
     * Plans and transactionally persists a Notification for durable delivery.
     * @returns NotificationPublication
     */
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

    /**
     * Sends a populated Notification synchronously through its enabled channels.
     * @returns BaseNotification
     */
    public BaseNotification function notify( required any notification, struct properties = {} ) {
        return variables.notificationService.notify( $parent, arguments.notification, arguments.properties );
    }

}
