component accessors="true" {

    property name="id";

    property
        name="wireboxId"
        inject="wirebox:targetId"
        getter="false"
        setter="false";

    public array function via() {
        throw(
            type = "Megaphone.Notification.MissingAbstractMethod",
            message = "The `via` method must be implemented in a concrete notification component."
        );
    }

    public BaseNotification function populate( struct properties = {} ) {
        if ( isNull( variables.queuedProperties ) ) {
            variables.queuedProperties = {};
        }
        variables.queuedProperties.append( duplicate( arguments.properties ), true );
        for ( var key in arguments.properties ) {
            variables[ key ] = arguments.properties[ key ];
        }
        return this;
    }

    public struct function getQueueProperties() {
        return duplicate( variables.queuedProperties ?: {} );
    }

    public struct function getChannelPreferences( required any notifiable, array channelNames ) {
        var preferences = {};
        for (
            var channelName in ( isNull( arguments.channelNames ) ? via( arguments.notifiable ) : arguments.channelNames )
        ) {
            preferences[ channelName ] = { "enabled": true, "source": "notification" };
        }
        return preferences;
    }

    public struct function getDeliveryContext( required any notifiable, required string channelName ) {
        return {};
    }

    public string function getNotificationMapping() {
        return variables.wireboxId;
    }

    public any function routeForType(
        required string type,
        required any notifiable,
        required string channelName,
        struct additionalArgs = {}
    ) {
        if ( !structKeyExists( variables, "to" & arguments.type ) ) {
            var routingMethodName = str().camel( "to_#arguments.type#" );
            throw(
                type = "Megaphone.Notification.MissingRoutingMethod",
                message = "The `#routingMethodName#` method must be implemented in order to route to the `#channelName#` channel."
            );
        }

        var args = [ "notifiable": arguments.notifiable ];
        args.append( arguments.additionalArgs, false );

        return invoke( this, "to" & arguments.type, args );
    }

    public string function getNotificationType() {
        return variables.wireboxId;
    }

    private Str function str() provider="Str@Str" {
    }

}
