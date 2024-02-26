component {

    public string function getProviderName() {
        return "CustomProvider";
    }

    public BaseNotification function notify( required any notifiable, required BaseNotification notification ) {
        application.customNotificationSent = arguments.notification.routeForType(
            "custom",
            arguments.notifiable,
            getProviderName()
        );
        return arguments.notification;
    }

}
