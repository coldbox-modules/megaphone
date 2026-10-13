component singleton accessors="true" {

    property name="uuid" inject="java:java.util.UUID";
    property name="wirebox" inject="wirebox";

    property name="channels";

    /**
     * Initializes the registry of configured notification channels.
     * @returns NotificationService
     */
    public NotificationService function init() {
        variables.channels = {};
        return this;
    }

    /**
     * Sends a populated Notification synchronously through its enabled channels.
     * @returns BaseNotification
     */
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
            var channelNames = notification.via( notifiable );
            var preferences = notification.getChannelPreferences( notifiable, channelNames );
            channelNames.each( ( channelName ) => {
                if ( !preferences[ channelName ].enabled ) {
                    return;
                }
                var channel = getChannel( channelName );
                channel.notify( notifiable, uniqueNotification );
            } );
        } );
        return arguments.notification;
    }

    /**
     * Captures recipients, channel choices, device destinations, properties, and hashes without writing or sending.
     * @returns NotificationPlan
     */
    public NotificationPlan function plan(
        required any notifiables,
        required any notification,
        struct properties = {},
        struct options = {},
        string connection,
        string queue
    ) {
        var queueOptions = {};
        for ( var name in [ "connection", "queue" ] ) {
            if ( !isNull( arguments[ name ] ) ) {
                queueOptions[ name ] = arguments[ name ];
            }
        }
        var runtime = newNotificationRuntime();
        var snapshotter = newSnapshotHasher();
        if ( isSimpleValue( arguments.notification ) ) {
            arguments.notification = variables.wirebox.getInstance( arguments.notification );
        }
        arguments.notification.populate( arguments.properties );
        var occurredAt = arguments.options.keyExists( "occurredAt" ) ? arguments.options.occurredAt : now();
        var event = {
            "namespace": arguments.options.keyExists( "namespace" ) ? arguments.options.namespace : "megaphone",
            "eventKey": arguments.options.keyExists( "eventKey" ) ? arguments.options.eventKey : variables.uuid
                .randomUUID()
                .toString(),
            "version": arguments.options.keyExists( "version" ) ? arguments.options.version : 1,
            "type": arguments.notification.getNotificationType(),
            "notificationMapping": arguments.notification.getNotificationMapping(),
            "payload": snapshotter.snapshot( arguments.notification.getQueueProperties() ),
            "createdDate": occurredAt
        };
        if ( !isDate( occurredAt ) ) {
            throw(
                type = "Megaphone.Events.OccurrenceRequired",
                message = "Notification occurrence time must be a valid date."
            );
        }
        if (
            !isSimpleValue( event.namespace ) || !len( trim( event.namespace ) ) || !isSimpleValue( event.eventKey ) || !len(
                trim( event.eventKey )
            ) || !isNumeric( event.version ) || event.version < 1 || fix( event.version ) != event.version
        ) {
            throw(
                type = "Megaphone.Events.InvalidIdentity",
                message = "Event identity and a positive integer version are required."
            );
        }
        event.payloadHash = runtime.digest( event.payload, { "namespace": event.namespace, "kind": "payload" } );
        var plan = new megaphone.models.NotificationPlan(
            event,
            [],
            arguments.options.admitAfter ?: javacast( "null", "" ),
            queueOptions
        );
        if ( !isNull( arguments.options.admitAfter ) && dateCompare( occurredAt, arguments.options.admitAfter ) < 0 ) {
            event.expired = true;
            plan = new megaphone.models.NotificationPlan(
                event,
                [],
                arguments.options.admitAfter,
                queueOptions
            );
            return plan;
        }
        var intents = [];
        var seen = {};
        for ( var notifiable in arrayWrap( arguments.notifiables ) ) {
            var ownerKey = serializeJSON( [ notifiable.getNotifiableType(), toString( notifiable.getNotifiableId() ) ] );
            if ( seen.keyExists( ownerKey ) ) {
                continue;
            }
            seen[ ownerKey ] = true;
            var channelNames = arguments.notification.via( notifiable );
            var preferences = arguments.notification.getChannelPreferences( notifiable, channelNames );
            for ( var channelName in channelNames ) {
                var channel = getChannel( channelName );
                if (
                    !isCustomFunction( channel.prepareDelivery ?: "" ) || !isCustomFunction(
                        channel.sendDelivery ?: ""
                    ) || ( isCustomFunction( channel.supportsDurableDelivery ?: "" ) && !channel.supportsDurableDelivery() )
                ) {
                    throw(
                        type = "Megaphone.Configuration.UnsupportedDurableProvider",
                        message = "Channel [#channelName#] does not support durable delivery."
                    );
                }
                if (
                    !isStruct( preferences[ channelName ] ?: "" ) || !structKeyExists(
                        preferences[ channelName ],
                        "enabled"
                    ) || !isBoolean( preferences[ channelName ].enabled )
                ) {
                    throw(
                        type = "Megaphone.Preferences.InvalidChoice",
                        message = "Every planned channel requires an explicit enabled preference."
                    );
                }
                var routing = snapshotter.snapshot(
                    arguments.notification.getDeliveryContext( notifiable, channelName )
                );
                var enabled = preferences[ channelName ].enabled;
                var targets = [ "" ];
                if ( enabled && isCustomFunction( channel.getDeliveryTargets ?: "" ) ) {
                    targets = channel.getDeliveryTargets( notifiable, arguments.notification );
                    if ( targets.isEmpty() ) {
                        targets = [ "" ];
                        enabled = false;
                    }
                }
                var seenTargets = {};
                for ( var deviceId in targets ) {
                    if ( seenTargets.keyExists( deviceId ) ) {
                        continue;
                    }
                    seenTargets[ deviceId ] = true;
                    intents.append( {
                        "notifiableType": notifiable.getNotifiableType(),
                        "notifiableId": toString( notifiable.getNotifiableId() ),
                        "channelName": channelName,
                        "deviceId": deviceId,
                        "enabled": enabled,
                        "routingData": routing,
                        "routingHash": runtime.digest( routing, { "namespace": event.namespace, "kind": "routing" } ),
                        "availableDate": arguments.options.availableDate ?: now()
                    } );
                }
            }
        }
        return new megaphone.models.NotificationPlan(
            event,
            intents,
            arguments.options.admitAfter ?: javacast( "null", "" ),
            queueOptions
        );
    }

    /**
     * Plans and transactionally persists a Notification for durable delivery.
     * @returns NotificationPublication
     */
    public NotificationPublication function queue(
        required any notifiables,
        required any notification,
        struct properties = {},
        struct options = {},
        string connection,
        string queue
    ) {
        return queuePlan( plan( argumentCollection = arguments ) );
    }

    /**
     * Persists a saved plan without expanding its audience or re-enabling suppressed work.
     * @returns NotificationPublication
     */
    public NotificationPublication function queuePlan(
        required NotificationPlan plan,
        boolean alreadyAdmitted = false,
        string connection,
        string queue
    ) {
        var captured = arguments.plan.getMemento();
        var queueOptions = arguments.plan.getQueueOptions();
        for ( var name in [ "connection", "queue" ] ) {
            if ( !isNull( arguments[ name ] ) ) {
                queueOptions[ name ] = arguments[ name ];
            }
        }
        if (
            !arguments.alreadyAdmitted && !isNull( captured.admitAfter ) && dateCompare(
                captured.event.createdDate,
                captured.admitAfter
            ) < 0
        ) {
            return new megaphone.models.NotificationPublication(
                new megaphone.models.NotificationEvent( { "expired": true } )
            );
        }
        var queueAdapter = newNotificationRuntime().resolve( "queueAdapter" );
        var service = newDeliveryService();
        transaction {
            try {
                var event = service.recordEvent( argumentCollection = captured.event );
                if ( !event.getCreated() ) {
                    return new megaphone.models.NotificationPublication(
                        event,
                        service.getDeliveriesForEvent( event.getId() )
                    );
                }
                var deliveries = [];
                for ( var intent in captured.deliveries ) {
                    var delivery = service.createDelivery( event.getId(), intent );
                    deliveries.append( delivery );
                    if ( delivery.getCreated() && delivery.getState() == "queued" && !isNull( queueAdapter ) ) {
                        var enqueueArguments = duplicate( queueOptions );
                        enqueueArguments.delivery = delivery;
                        queueAdapter.enqueue( argumentCollection = enqueueArguments );
                    }
                }
                return new megaphone.models.NotificationPublication( event, deliveries );
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
    }


    /**
     * Registers Provider instances under the configured channel names.
     * @returns NotificationService
     */
    public NotificationService function registerChannels( required struct channels, boolean overwrite = false ) {
        if ( arguments.overwrite ) {
            variables.channels = {};
        }

        for ( var key in arguments.channels ) {
            var configuration = arguments.channels[ key ];
            variables.channels[ key ] = variables.wirebox.getInstance(
                configuration.provider,
                { "name": key, "properties": configuration.properties }
            );
        }

        return this;
    }

    /**
     * Returns the channel to send the notification on.
     *
     * @channelName The channel name or WireBox mapping name that implements `INotificationProvider`.
     *
     * @returns     A component that implements `INotificationProvider`.
     */
    public any function getChannel( required string channelName ) {
        if ( variables.channels.keyExists( arguments.channelName ) ) {
            return variables.channels[ arguments.channelName ];
        }

        if ( variables.wirebox.getBinder().mappingExists( channelName ) ) {
            return variables.wirebox.getInstance( channelName );
        }

        throw(
            type = "Megaphone.Configuration.MissingChannel",
            message = "Channel [#channelName#] is not configured in your settings and is not available in WireBox.  Add it to your `channels` key in your `megaphone` config struct.",
            detail = "Found channels are: [#structKeyList( variables.channels ) ?: ""#]"
        );
    }

    /**
     * Normalizes one Notifiable or an array into an array.
     * @returns array
     */
    private array function arrayWrap( required any items ) {
        return isArray( arguments.items ) ? arguments.items : [ arguments.items ];
    }

    /**
     * Supplies the lazy notification runtime through WireBox.
     * @returns any
     */
    private any function newNotificationRuntime() provider="NotificationRuntime@megaphone" {
    }
    /**
     * Supplies the default deterministic snapshot hasher through WireBox.
     * @returns any
     */
    private any function newSnapshotHasher() provider="NotificationSnapshotHasher@megaphone" {
    }
    /**
     * Supplies the delivery operations service through WireBox.
     * @returns any
     */
    private any function newDeliveryService() provider="NotificationDeliveryService@megaphone" {
    }

}
