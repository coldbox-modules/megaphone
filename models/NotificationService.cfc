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
            var uniqueNotification = copyNotification( notification ).setId( variables.uuid.randomUUID().toString() );
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
        return capturePlan( argumentCollection = arguments );
    }

    private NotificationPlan function capturePlan(
        required any notifiables,
        required any notification,
        struct properties = {},
        struct options = {},
        string connection,
        string queue,
        boolean deferHashes = false
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
        event.payloadHash = arguments.deferHashes ? "" : runtime.digest(
            event.payload,
            { "namespace": event.namespace, "kind": "payload" }
        );
        if ( !isNull( arguments.options.admitAfter ) && dateCompare( occurredAt, arguments.options.admitAfter ) < 0 ) {
            event.expired = true;
            return newNotificationPlan().configure(
                event,
                [],
                arguments.options.admitAfter,
                queueOptions
            );
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
                var collects = isCustomFunction( channel.supportsCollection ?: "" ) && channel.supportsCollection();
                if (
                    !collects && (
                        !isCustomFunction( channel.prepareDelivery ?: "" ) || !isCustomFunction(
                            channel.sendDelivery ?: ""
                        ) || (
                            isCustomFunction( channel.supportsDurableDelivery ?: "" ) && !channel.supportsDurableDelivery()
                        )
                    )
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
                if ( collects ) {
                    routing.emailDigest = snapshotter.snapshot(
                        channel.getCollectionIntent( notifiable, arguments.notification )
                    );
                }
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
                        "collection": collects,
                        "deviceId": deviceId,
                        "enabled": enabled,
                        "routingData": routing,
                        "routingHash": arguments.deferHashes ? "" : runtime.digest(
                            routing,
                            { "namespace": event.namespace, "kind": "routing" }
                        ),
                        "availableDate": arguments.options.availableDate ?: now()
                    } );
                }
            }
        }
        return newNotificationPlan().configure(
            event,
            intents,
            arguments.options.admitAfter ?: javacast( "null", "" ),
            queueOptions
        );
    }

    /** Captures ordinary plan() requests and hashes their snapshots together in input order. */
    public array function planMany( required array requests ) {
        var plans = [];
        var captures = [];
        var hashes = [];
        for ( var inputRequest in arguments.requests ) {
            var options = structCopy( inputRequest );
            options.deferHashes = true;
            var plan = capturePlan( argumentCollection = options );
            var captured = plan.getMemento();
            plans.append( plan );
            captures.append( captured );
            hashes.append( { "value": captured.event.payload, "context": { "namespace": captured.event.namespace, "kind": "payload" } } );
            for ( var intent in captured.deliveries ) {
                hashes.append( { "value": intent.routingData, "context": { "namespace": captured.event.namespace, "kind": "routing" } } );
            }
        }
        if ( hashes.isEmpty() ) {
            return plans;
        }
        var digests = newNotificationRuntime().digestMany( hashes );
        var cursor = 1;
        for ( var index = 1; index <= plans.len(); index++ ) {
            var captured = captures[ index ];
            captured.event.payloadHash = digests[ cursor++ ];
            for ( var intent in captured.deliveries ) {
                intent.routingHash = digests[ cursor++ ];
            }
            var argumentsForPlan = {
                "event": captured.event,
                "deliveries": captured.deliveries,
                "queueOptions": plans[ index ].getQueueOptions()
            };
            if ( !isNull( captured.admitAfter ) ) {
                argumentsForPlan.admitAfter = captured.admitAfter;
            }
            plans[ index ].configure( argumentCollection = argumentsForPlan );
        }
        return plans;
    }

    /** All plans share one publication transaction, including legacy adapter and digest fallbacks. */
    public array function queuePlans(
        required array plans,
        boolean alreadyAdmitted = false,
        string connection,
        string queue
    ) {
        var result = [];
        if ( arguments.plans.isEmpty() ) {
            return result;
        }
        var runtime = newNotificationRuntime();
        var settings = runtime.getSettings();
        var captures = arguments.plans.map( ( plan ) => plan.getMemento() );
        var fallback = structKeyExists( settings, "digests" ) && !structIsEmpty( settings.digests );
        for ( var captured in captures ) {
            for ( var intent in captured.deliveries ) {
                fallback = fallback || ( intent.collection ?: false ) || structKeyExists(
                    intent.routingData,
                    "emailDigest"
                );
            }
        }
        transaction {
            try {
                if ( fallback ) {
                    for ( var plan in arguments.plans ) {
                        var original = { "plan": plan, "alreadyAdmitted": arguments.alreadyAdmitted };
                        for ( var key in [ "connection", "queue" ] ) {
                            if ( !isNull( arguments[ key ] ) ) {
                                original[ key ] = arguments[ key ];
                            }
                        }
                        result.append( queuePlan( argumentCollection = original ) );
                    }
                    return result;
                }
                var active = [];
                var ordinals = [];
                for ( var index = 1; index <= captures.len(); index++ ) {
                    var captured = captures[ index ];
                    if (
                        !arguments.alreadyAdmitted && !isNull( captured.admitAfter ) && dateCompare(
                            captured.event.createdDate,
                            captured.admitAfter
                        ) < 0
                    ) {
                        result.append(
                            newNotificationPublication().configure(
                                newNotificationEvent().configure( { "expired": true } )
                            )
                        );
                    } else {
                        result.append( "" );
                        active.append( captured.event );
                        ordinals.append( index );
                    }
                }
                if ( active.isEmpty() ) {
                    return result;
                }
                var service = newDeliveryService();
                var events = service.recordEvents( active );
                var entries = [];
                var deliveryIndexes = {};
                for ( var index = 1; index <= events.len(); index++ ) {
                    var event = events[ index ];
                    if ( event.getCreated() ) {
                        deliveryIndexes[ event.getId() ] = [];
                        for ( var intent in captures[ ordinals[ index ] ].deliveries ) {
                            entries.append( { "eventId": event.getId(), "intent": intent } );
                            deliveryIndexes[ event.getId() ].append( entries.len() );
                        }
                    }
                }
                var admitted = service.createDeliveries( entries );
                var stored = service.getDeliveriesForEvents(
                    events.filter( ( event ) => !event.getCreated() ).map( ( event ) => event.getId() )
                );
                var byEvent = {};
                for ( var delivery in stored ) {
                    if ( !structKeyExists( byEvent, delivery.getEventId() ) ) {
                        byEvent[ delivery.getEventId() ] = [];
                    }
                    byEvent[ delivery.getEventId() ].append( delivery );
                }
                var groups = {};
                for ( var index = 1; index <= events.len(); index++ ) {
                    var event = events[ index ];
                    var deliveries = [];
                    if ( event.getCreated() ) {
                        for ( var position in deliveryIndexes[ event.getId() ] ) {
                            deliveries.append( admitted[ position ] );
                        }
                    } else {
                        deliveries = byEvent[ event.getId() ] ?: [];
                    }
                    result[ ordinals[ index ] ] = newNotificationPublication().configure( event, deliveries );
                    var queueOptions = arguments.plans[ ordinals[ index ] ].getQueueOptions();
                    for ( var key in [ "connection", "queue" ] ) {
                        if ( !isNull( arguments[ key ] ) ) {
                            queueOptions[ key ] = arguments[ key ];
                        }
                    }
                    var groupKey = hash(
                        serializeJSON( [
                            queueOptions.connection ?: javacast( "null", "" ),
                            queueOptions.queue ?: javacast( "null", "" )
                        ] ),
                        "SHA-256"
                    );
                    if ( !structKeyExists( groups, groupKey ) ) {
                        groups[ groupKey ] = { "options": queueOptions, "deliveries": [] };
                    }
                    for ( var delivery in deliveries ) {
                        if ( event.getCreated() && delivery.getCreated() && delivery.getState() == "queued" ) {
                            groups[ groupKey ].deliveries.append( delivery );
                        }
                    }
                }
                var adapter = runtime.resolve( "queueAdapter" );
                if ( !isNull( adapter ) ) {
                    for ( var key in groups ) {
                        var group = groups[ key ];
                        if ( group.deliveries.isEmpty() ) {
                            continue;
                        }
                        if ( isCustomFunction( adapter.enqueueMany ?: "" ) ) {
                            var enqueueArguments = duplicate( group.options );
                            enqueueArguments.deliveries = group.deliveries;
                            adapter.enqueueMany( argumentCollection = enqueueArguments );
                        } else {
                            for ( var delivery in group.deliveries ) {
                                var enqueueArguments = duplicate( group.options );
                                enqueueArguments.delivery = delivery;
                                adapter.enqueue( argumentCollection = enqueueArguments );
                            }
                        }
                    }
                }
                return result;
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
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
            return newNotificationPublication().configure( newNotificationEvent().configure( { "expired": true } ) );
        }
        var queueAdapter = newNotificationRuntime().resolve( "queueAdapter" );
        var service = newDeliveryService();
        transaction {
            try {
                var event = service.recordEvent( argumentCollection = captured.event );
                if ( !event.getCreated() ) {
                    var storedCollections = getStoredCollections( captured.deliveries, event.getId() );
                    var storedDeliveries = service.getDeliveriesForEvent( event.getId() );
                    for ( var collected in storedCollections ) {
                        if ( len( collected.deliveryId ?: "" ) ) {
                            storedDeliveries.append( service.getDelivery( collected.deliveryId ) );
                        }
                    }
                    return newNotificationPublication().configure( event, storedDeliveries, storedCollections );
                }
                var deliveries = [];
                var collections = [];
                for ( var intent in captured.deliveries ) {
                    if ( structKeyExists( intent, "collection" ) && intent.collection ) {
                        var channel = getChannel( intent.channelName );
                        if ( !isCustomFunction( channel.supportsCollection ?: "" ) || !channel.supportsCollection() ) {
                            throw(
                                type = "Megaphone.Digests.CollectionChannelChanged",
                                message = "A saved collection plan requires its collection provider."
                            );
                        }
                        var collected = channel.collectPlanned( event, intent );
                        collections.append( collected );
                        if ( len( collected.deliveryId ?: "" ) ) {
                            var immediateDelivery = service.getDelivery( collected.deliveryId );
                            deliveries.append( immediateDelivery );
                            var queueImmediate = collected.created && immediateDelivery.getState() == "queued";
                            if ( queueImmediate && !isNull( queueAdapter ) ) {
                                var enqueueArguments = duplicate( queueOptions );
                                enqueueArguments.delivery = immediateDelivery;
                                queueAdapter.enqueue( argumentCollection = enqueueArguments );
                            }
                        }
                        continue;
                    }
                    var delivery = service.createDelivery( event.getId(), intent );
                    deliveries.append( delivery );
                    if ( delivery.getCreated() && delivery.getState() == "queued" && !isNull( queueAdapter ) ) {
                        var enqueueArguments = duplicate( queueOptions );
                        enqueueArguments.delivery = delivery;
                        queueAdapter.enqueue( argumentCollection = enqueueArguments );
                    }
                }
                return newNotificationPublication().configure( event, deliveries, collections );
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
     * Copies notification state for one recipient without cloning WireBox's shared collaborators on BoxLang.
     * The shallow staging copy keeps the original instance intact; the second copy isolates its data.
     *
     * @notification The populated notification whose ID and data must remain unchanged.
     * @returns BaseNotification
     */
    private BaseNotification function copyNotification( required BaseNotification notification ) {
        if ( !structKeyExists( server, "boxlang" ) || !structKeyExists( arguments.notification, "$wbInjector" ) ) {
            return duplicate( arguments.notification );
        }
        // Invoke dynamically because Adobe validates duplicate() argument counts even in this BoxLang-only branch.
        var staged = invoke( "", "duplicate", [ arguments.notification, false ] );
        var injector = staged.$wbInjector;
        structDelete( staged, "$wbInjector" );
        var scopes = { "variables": staged.getVariablesMixin(), "this": staged };
        var injections = [];
        var mapping = injector.getBinder().getMapping( arguments.notification.getNotificationMapping() );
        for ( var dependency in mapping.getDIProperties() ) {
            var scope = scopes[ dependency.scope ];
            if ( structKeyExists( scope, dependency.name ) ) {
                injections.append( { "scope": dependency.scope, "name": dependency.name, "value": scope[ dependency.name ] } );
                structDelete( scope, dependency.name );
            }
        }
        var copied = duplicate( staged );
        copied.$wbInjector = injector;
        var copiedScopes = { "variables": copied.getVariablesMixin(), "this": copied };
        for ( var injection in injections ) {
            copiedScopes[ injection.scope ][ injection.name ] = injection.value;
        }
        return copied;
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

    /**
     * Returns existing event admissions without collecting again or expanding the saved audience.
     * @returns array
     */
    private array function getStoredCollections( required array intents, required string eventId ) {
        var runtimeSettings = newNotificationRuntime().getSettings();
        if ( structKeyExists( runtimeSettings, "digests" ) && !structIsEmpty( runtimeSettings.digests ) ) {
            return newDigestService().getCollectionsForEvent( arguments.eventId );
        }
        for ( var intent in arguments.intents ) {
            if ( structKeyExists( intent.routingData, "emailDigest" ) ) {
                return newDigestService().getCollectionsForEvent( arguments.eventId );
            }
        }
        return [];
    }

    /**
     * Supplies the named digest service through WireBox.
     * @returns any
     */
    private any function newDigestService() provider="EmailDigestService@megaphone" {
    }

    /**
     * Supplies a fresh NotificationEvent using the application's WireBox mapping.
     * @returns NotificationEvent
     */
    private NotificationEvent function newNotificationEvent() provider="NotificationEvent@megaphone" {
    }

    /**
     * Supplies a fresh NotificationPlan using the application's WireBox mapping.
     * @returns NotificationPlan
     */
    private NotificationPlan function newNotificationPlan() provider="NotificationPlan@megaphone" {
    }

    /**
     * Supplies a fresh NotificationPublication using the application's WireBox mapping.
     * @returns NotificationPublication
     */
    private NotificationPublication function newNotificationPublication() provider="NotificationPublication@megaphone" {
    }

}
