component accessors="true" {

    property name="str" inject="@str";

    property name="name" type="string";
    property name="properties" type="struct";

    public string function getProviderName() {
        throw(
            type = "Megaphone.Providers.MissingAbstractMethod",
            message = "The getProviderName() method must be implemented by the provider."
        );
    }

    public BaseNotification function notify( required any notifiable, required BaseNotification notification ) {
        throw(
            type = "Megaphone.Providers.MissingAbstractMethod",
            message = "The notify() method must be implemented by the provider."
        );
    }

    public any function routeNotificationFor(
        required string type,
        required any notifiable,
        required string channelName
    ) {
        var methodName = "routeNotificationFor" & arguments.type;
        if ( !structKeyExists( notifiable, methodName ) ) {
            var routingToMethodName = variables.str.camel( "to_#arguments.type#" );
            var routingForMethodName = variables.str.camel( "route_notification_for_#arguments.type#" );
            throw(
                type = "Megaphone.Notification.MissingRoutingForMethod",
                message = "Unable to determine where to route your notification for the `#arguments.channelName#` channel. Either explicitly set the route in your `#routingToMethodName#` or provide a `#routingForMethodName#` on your notifiable instance."
            );
        }

        return invoke( arguments.notifiable, methodName );
    }

}
