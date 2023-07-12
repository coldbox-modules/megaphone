component singleton accessors="true" {

    property name="uuid" inject="java:java.util.UUID";
    property name="wirebox" inject="wirebox";

    property name="channels";

    public NotificationService function init() {
        variables.channels = {};
        return this;
    }

    public BaseNotification function notify(
        required any notifiables,
        required any notification,
        struct properties = {}
    ) {
        if ( isSimpleValue( arguments.notification ) ) {
            arguments.notification = variables.wirebox.getInstance( arguments.notification );
        }
        arguments.notification.populate( arguments.properties );
        arrayWrap( arguments.notifiables ).each( ( notifiable ) => {
            var uniqueNotification = duplicate( notification ).setId( variables.uuid.randomUUID().toString() );
            notification
                .via( notifiable )
                .each( ( channelName ) => {
                    var channel = getChannel( channelName );
                    channel.notify( notifiable, uniqueNotification );
                } );
        } );
        return arguments.notification;
    }


    public NotificationService function registerChannels( required struct channels, boolean overwrite = false ) {
        if ( arguments.overwrite ) {
            variables.channels = {};
        }

        for ( var key in arguments.channels ) {
            var configuration = arguments.channels[ key ];
            variables.channels[ key ] = variables.wirebox
                .getInstance( configuration.provider )
                .setProperties( configuration.properties )
                .setName( key );
        }

        return this;
    }

    public BaseProvider function getChannel( required string channelName ) {
        if ( !variables.channels.keyExists( arguments.channelName ) ) {
            throw(
                type = "Megaphone.Configuration.MissingChannel",
                message = "Channel [#channelName#] is not configured in your settings.  Add it to your `channels` key in your `megaphone` config struct.",
                detail = "Found channels are: [#structKeyList( variables.channels ) ?: ""#]"
            );
        }
        return variables.channels[ arguments.channelName ];
    }

    private array function arrayWrap( required any items ) {
        return isArray( arguments.items ) ? arguments.items : [ arguments.items ];
    }

}
