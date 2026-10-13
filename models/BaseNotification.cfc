component accessors="true" {

    property name="id";

    property
        name="wireboxId"
        inject="wirebox:targetId"
        getter="false"
        setter="false";

    /**
     * Chooses the configured delivery channels for a Notifiable.
     * @returns array
     */
    public array function via() {
        throw(
            type = "Megaphone.Notification.MissingAbstractMethod",
            message = "The `via` method must be implemented in a concrete notification component."
        );
    }

    /**
     * Populates Notification properties and keeps their durable snapshot.
     * @returns BaseNotification
     */
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

    /**
     * Returns the populated properties that can be saved for a queued Notification.
     * @returns struct
     */
    public struct function getQueueProperties() {
        return duplicate( variables.queuedProperties ?: {} );
    }

    /**
     * Returns enabled/source decisions for the channels offered to this Notifiable.
     * @returns struct
     */
    public struct function getChannelPreferences( required any notifiable, array channelNames ) {
        var preferences = {};
        for (
            var channelName in ( isNull( arguments.channelNames ) ? via( arguments.notifiable ) : arguments.channelNames )
        ) {
            preferences[ channelName ] = { "enabled": true, "source": "notification" };
        }
        return preferences;
    }

    /**
     * Returns application routing context to capture with this channel delivery.
     * @returns struct
     */
    public struct function getDeliveryContext( required any notifiable, required string channelName ) {
        return {};
    }

    /**
     * Returns the WireBox name or component path used to reconstruct this Notification.
     * @returns string
     */
    public string function getNotificationMapping() {
        return isNull( variables.wireboxId ) ? getMetadata( this ).name : variables.wireboxId;
    }

    /**
     * Calls the Notification formatter for a Provider type, passing its additional arguments.
     * @returns any
     */
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

    /**
     * Returns the identity used for stored notification types and preferences.
     * @returns string
     */
    public string function getNotificationType() {
        return isNull( variables.wireboxId ) ? getMetadata( this ).name : variables.wireboxId;
    }

    /**
     * Supplies the string helper used to derive formatter method names.
     * @returns Str
     */
    private Str function str() provider="Str@Str" {
    }

}
