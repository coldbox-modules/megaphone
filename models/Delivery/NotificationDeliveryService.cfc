/** Public durable-delivery boundary. Storage owns leases; providers own I/O. */
component singleton {

    property name="eventStore" inject="EventStore@megaphone";
    property name="deliveryStore" inject="DeliveryStore@megaphone";
    property name="runtime" inject="NotificationRuntime@megaphone";
    property name="wirebox" inject="wirebox";

    /**
     * Records an event and returns its public NotificationEvent object.
     * @returns NotificationEvent
     */
    public NotificationEvent function recordEvent(
        required string namespace,
        required string eventKey,
        required numeric version,
        required string type,
        required struct payload,
        required string payloadHash,
        date createdDate = now(),
        string notificationMapping = ""
    ) {
        return newNotificationEvent().configure( variables.eventStore.record( argumentCollection = arguments ) );
    }

    /** Records an atomic batch through the configured event store. */
    public array function recordEvents( required array events ) {
        return variables.eventStore
            .recordMany( arguments.events )
            .map( ( row ) => newNotificationEvent().configure( row ) );
    }

    /**
     * Loads a public event object by ID, or returns null.
     * @returns any
     */
    public any function getEvent( required string id ) {
        var row = variables.eventStore.find( arguments.id );
        if ( isNull( row ) ) {
            return;
        }
        return newNotificationEvent().configure( row );
    }

    /**
     * Loads a delivery object by ID, or returns null.
     * @returns any
     */
    public any function getDelivery( required string id, boolean lockRow = false ) {
        var row = variables.deliveryStore.find( argumentCollection = arguments );
        if ( isNull( row ) ) {
            return;
        }
        return delivery( row );
    }

    /**
     * Persists a delivery intent and returns its NotificationDelivery object.
     * @returns NotificationDelivery
     */
    public NotificationDelivery function createDelivery( required string eventId, required struct intent ) {
        if ( !structKeyExists( arguments.intent, "enabled" ) || !isBoolean( arguments.intent.enabled ) ) {
            throw(
                type = "Megaphone.Delivery.InvalidIntent",
                message = "Every delivery needs an explicit channel choice."
            );
        }
        var values = storageIntent( arguments.intent );
        values.eventId = arguments.eventId;
        values.initialState = arguments.intent.enabled ? "queued" : "suppressed";
        return delivery( variables.deliveryStore.enqueue( argumentCollection = values ) );
    }

    /** Creates an ordered batch of public delivery intents without provider I/O. */
    public array function createDeliveries( required array entries ) {
        var intents = [];
        for ( var entry in arguments.entries ) {
            if ( !structKeyExists( entry.intent, "enabled" ) || !isBoolean( entry.intent.enabled ) ) {
                throw(
                    type = "Megaphone.Delivery.InvalidIntent",
                    message = "Every delivery needs an explicit channel choice."
                );
            }
            var values = storageIntent( entry.intent );
            values.eventId = entry.eventId;
            values.initialState = entry.intent.enabled ? "queued" : "suppressed";
            intents.append( values );
        }
        return variables.deliveryStore.enqueueMany( intents ).map( ( row ) => delivery( row ) );
    }

    /** Loads persisted work for a bounded set of events without expanding its audience. */
    public array function getDeliveriesForEvents( required array eventIds ) {
        return variables.deliveryStore.forEvents( arguments.eventIds ).map( ( row ) => delivery( row ) );
    }

    /**
     * Imports delivery history while preserving stable IDs and acceptance evidence.
     * @returns NotificationDelivery
     */
    public NotificationDelivery function importDelivery( required struct intent, required struct history ) {
        return delivery(
            variables.deliveryStore.importDelivery( storageIntent( arguments.intent ), arguments.history )
        );
    }

    /**
     * Returns the delivery objects belonging to an event.
     * @returns array
     */
    public array function getDeliveriesForEvent( required string eventId ) {
        return variables.deliveryStore.forEvent( arguments.eventId ).map( ( row ) => delivery( row ) );
    }

    /**
     * Returns a bounded page of public delivery objects using application constraints.
     * @returns NotificationDeliveryPage
     */
    public NotificationDeliveryPage function getDeliveries( numeric maxRows = 50, numeric offset = 0, any constraints ) {
        var page = variables.deliveryStore.getPage( argumentCollection = arguments );
        return newNotificationDeliveryPage().configure( page.results.map( ( row ) => delivery( row ) ), page.hasMore );
    }

    /**
     * Counts delivery states after applying the application's constraints.
     * @returns array
     */
    public array function getStateCounts( any constraints ) {
        return variables.deliveryStore
            .stateCounts( argumentCollection = arguments )
            .map( ( row ) => {
                return { "channelName": row.channel, "state": row.state, "total": row.total };
            } );
    }

    /**
     * Returns a bounded set of deliveries eligible for worker pickup.
     * @returns array
     */
    public array function getDueDeliveries( numeric limit = 100, date clock = now(), any constraints ) {
        return variables.deliveryStore.due( argumentCollection = arguments ).map( ( row ) => delivery( row ) );
    }

    /**
     * Returns public attempt objects for a delivery.
     * @returns array
     */
    public array function getAttempts( required string id ) {
        return variables.deliveryStore
            .attempts( arguments.id )
            .map( ( row ) => newNotificationDeliveryAttempt().configure( row ) );
    }
    /**
     * Returns a page of public recovery receipts for a delivery.
     * @returns NotificationRecoveryPage
     */
    public NotificationRecoveryPage function getRecoveryHistory(
        required string id,
        numeric maxRows = 20,
        numeric offset = 0
    ) {
        var page = variables.deliveryStore.recoveryHistory( argumentCollection = arguments );
        return newNotificationRecoveryPage().configure(
            page.results.map( ( row ) => newNotificationRecoveryReceipt().configure( row ) ),
            page.hasMore
        );
    }
    /**
     * Returns the fingerprint used to reject stale operator recovery requests.
     * @returns string
     */
    public string function getRecoveryVersion( required NotificationDelivery delivery ) {
        return variables.deliveryStore.recoveryVersion( storageIntent( arguments.delivery.getMemento() ) );
    }
    /**
     * Checks whether this delivery has an outcome eligible for explicit recovery.
     * @returns boolean
     */
    public boolean function canRecover( required NotificationDelivery delivery ) {
        return variables.deliveryStore.canRecover( storageIntent( arguments.delivery.getMemento() ) );
    }

    /**
     * Claims and prepares a delivery, rechecks eligibility, and records its transport outcome.
     * @returns DeliveryResult
     */
    public DeliveryResult function dispatch( required string id, struct options = {} ) {
        var dispatchPolicy = variables.runtime.resolve( "deliveryPolicy" );
        var configuredOptions = isNull( dispatchPolicy ) ? {} : dispatchPolicy.getDispatchOptions( arguments.id );
        configuredOptions.append( arguments.options, true );
        arguments.options = configuredOptions;
        var policy = variables.runtime.getSettings().queue;
        var leaseSeconds = arguments.options.keyExists( "leaseSeconds" ) ? arguments.options.leaseSeconds : policy.leaseSeconds;
        var maxAttempts = arguments.options.keyExists( "maxAttempts" ) ? arguments.options.maxAttempts : policy.maxAttempts;
        var retrySeconds = arguments.options.keyExists( "retrySeconds" ) ? arguments.options.retrySeconds : policy.retrySeconds;
        if ( retrySeconds < 1 || fix( retrySeconds ) != retrySeconds ) {
            throw( type = "Megaphone.Delivery.InvalidRetry", message = "Retry delay must be a positive integer." );
        }
        var claimed = variables.deliveryStore.claim( arguments.id, leaseSeconds, maxAttempts );
        if ( claimed.status != "ready" ) {
            return result( claimed.status );
        }
        var work = delivery( claimed.delivery );
        var prepared = "";
        var channel = "";
        try {
            var event = getEvent( work.getEventId() );
            if ( isNull( event ) ) {
                return settle(
                    work,
                    claimed.token,
                    result( "permanent", "event-missing" ),
                    retrySeconds
                );
            }
            var notifiable = variables.runtime.getNotifiable( work.getNotifiableType(), work.getNotifiableId() );
            if ( isNull( notifiable ) ) {
                return settle(
                    work,
                    claimed.token,
                    result( "suppressed", "notifiable-missing" ),
                    retrySeconds
                );
            }
            var loadedId = toString( notifiable.getNotifiableId() );
            var expectedId = work.getNotifiableId();
            var idMatches = isValid( "uuid", loadedId ) && isValid( "uuid", expectedId ) ? compareNoCase(
                loadedId,
                expectedId
            ) == 0 : compare( loadedId, expectedId ) == 0;
            if ( !idMatches || compare( notifiable.getNotifiableType(), work.getNotifiableType() ) != 0 ) {
                return settle(
                    work,
                    claimed.token,
                    result( "permanent", "notifiable-identity-mismatch" ),
                    retrySeconds
                );
            }
            var ready = checkEligibility( work, notifiable, event );
            if ( ready.getStatus() != "ready" ) {
                return settlePreparation(
                    work,
                    claimed.token,
                    ready,
                    retrySeconds
                );
            }
            if ( !len( event.getNotificationMapping() ) ) {
                throw(
                    type = "Megaphone.Configuration.MissingNotificationMapping",
                    message = "Stored notification has no reconstruction mapping."
                );
            }
            var notification = variables.wirebox
                .getInstance( event.getNotificationMapping() )
                .populate( event.getPayload() )
                .setId( work.getId() );
            var preferences = notification.getChannelPreferences( notifiable );
            if ( !preferences[ work.getChannelName() ].enabled ) {
                return settle(
                    work,
                    claimed.token,
                    result( "suppressed", "preference-disabled" ),
                    retrySeconds
                );
            }
            channel = variables.wirebox
                .getInstance( "NotificationService@megaphone" )
                .getChannel( work.getChannelName() );
            prepared = channel.prepareDelivery( notifiable, notification, work );
            if ( !isInstanceOf( prepared, "megaphone.models.Delivery.DeliveryPreparation" ) ) {
                throw(
                    type = "Megaphone.Delivery.InvalidPreparation",
                    message = "Providers must return a DeliveryPreparation."
                );
            }
            if ( prepared.getStatus() != "ready" ) {
                return settlePreparation(
                    work,
                    claimed.token,
                    prepared,
                    retrySeconds
                );
            }
            ready = checkEligibility( work, notifiable, event );
            if ( ready.getStatus() != "ready" ) {
                return settlePreparation(
                    work,
                    claimed.token,
                    ready,
                    retrySeconds
                );
            }
            // Rendering can outlive a preference change. Check again before marking transport started.
            if ( !notification.getChannelPreferences( notifiable )[ work.getChannelName() ].enabled ) {
                return settle(
                    work,
                    claimed.token,
                    result( "suppressed", "preference-disabled" ),
                    retrySeconds
                );
            }
        } catch ( any error ) {
            return settle(
                work,
                claimed.token,
                result( "retryable", "preparation-error" ),
                retrySeconds
            );
        }
        try {
            if ( isCustomFunction( channel.startDeliveryTransport ?: "" ) ) {
                var transport = channel.startDeliveryTransport( prepared, work, claimed.token );
                if ( !isInstanceOf( transport, "megaphone.models.Delivery.DeliveryPreparation" ) ) {
                    throw(
                        type = "Megaphone.Delivery.InvalidPreparation",
                        message = "Transport guards return DeliveryPreparation."
                    );
                }
                if ( transport.getStatus() != "ready" ) {
                    return settlePreparation(
                        work,
                        claimed.token,
                        transport,
                        retrySeconds
                    );
                }
            } else if ( !variables.deliveryStore.startTransport( work.getId(), claimed.token ) ) {
                return result( "superseded" );
            }
        } catch ( any error ) {
            return settle(
                work,
                claimed.token,
                result( "retryable", "transport-guard-error" ),
                retrySeconds
            );
        }
        var outcome = "";
        try {
            outcome = channel.sendDelivery( prepared, work );
            if (
                !isInstanceOf( outcome, "megaphone.models.Delivery.DeliveryResult" ) || !listFind(
                    "accepted,retryable,permanent,ambiguous",
                    outcome.getStatus()
                )
            ) {
                throw(
                    type = "Megaphone.Delivery.InvalidTransportResult",
                    message = "Providers must return a supported DeliveryResult."
                );
            }
        } catch ( any error ) {
            outcome = result( "ambiguous", "provider-outcome-unknown" );
        }
        return settle(
            work,
            claimed.token,
            outcome,
            retrySeconds
        );
    }

    /**
     * Requests bounded explicit recovery using a stable request key and current eligibility evidence.
     * @returns DeliveryRecoveryResult
     */
    public DeliveryRecoveryResult function requestRecovery(
        required string id,
        required string requestKey,
        required string actorId,
        required string expectedVersion,
        required function eligibility,
        required any queueAdapter,
        numeric additionalAttempts = 1,
        string actorLabel = "",
        date clock = now()
    ) {
        transaction {
            try {
                var work = getDelivery( arguments.id, true );
                if ( isNull( work ) ) {
                    return newDeliveryRecoveryResult().configure( { "status": "missing" } );
                }
                var saved = variables.deliveryStore.getRecoveryRequest( arguments.id, arguments.requestKey );
                if ( isNull( saved ) ) {
                    if ( !canRecover( work ) || getRecoveryVersion( work ) != arguments.expectedVersion ) {
                        return newDeliveryRecoveryResult().configure( { "status": "conflict" } );
                    }
                    var ready = arguments.eligibility( work );
                    if (
                        !isInstanceOf( ready, "megaphone.models.Delivery.DeliveryPreparation" ) || ready.getStatus() != "ready"
                    ) {
                        return newDeliveryRecoveryResult().configure( { "status": "ineligible" } );
                    }
                }
                var values = structCopy( arguments );
                structDelete( values, "eligibility" );
                structDelete( values, "queueAdapter" );
                var recovery = variables.deliveryStore.recover( argumentCollection = values );
                if ( recovery.status == "saved" ) {
                    recovery.delivery = delivery( recovery.delivery );
                    if ( !recovery.replayed ) {
                        arguments.queueAdapter.enqueue( recovery.delivery );
                    }
                }
                return newDeliveryRecoveryResult().configure( recovery );
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
    }

    /**
     * Reconciles a stored delivery against explicit application acceptance evidence.
     * @returns boolean
     */
    public boolean function reconcileAccepted( required string id, required function acceptance, date clock = now() ) {
        transaction {
            var work = getDelivery( arguments.id, true );
            if ( isNull( work ) ) {
                return false;
            }
            if ( work.getState() == "accepted" ) {
                return true;
            }
            var receipt = arguments.acceptance( work );
            return variables.deliveryStore.reconcileReceipt( arguments.id, receipt, arguments.clock );
        }
    }

    /**
     * Recovers expired leases without automatically retrying uncertain acceptance.
     * @returns numeric
     */
    public numeric function recoverExpired( numeric limit = 100, date clock = now(), any constraints ) {
        return variables.deliveryStore.recoverExpired( argumentCollection = arguments );
    }

    /**
     * Reconciles ambiguous work against authoritative local evidence that no attempt was accepted.
     * @returns boolean
     */
    public boolean function reconcileNotAccepted(
        required string id,
        required function rejection,
        date retryDate = now(),
        date clock = now()
    ) {
        transaction {
            var work = getDelivery( arguments.id, true );
            if ( isNull( work ) || work.getState() != "ambiguous" ) {
                return false;
            }
            return variables.deliveryStore.reconcileRejection(
                arguments.id,
                arguments.rejection( work ),
                arguments.retryDate,
                arguments.clock
            );
        }
    }
    /**
     * Deletes a bounded batch of eligible old transport attempts.
     * @returns numeric
     */
    public numeric function pruneAttempts( required date beforeDate, numeric limit = 200 ) {
        return variables.deliveryStore.pruneAttempts( argumentCollection = arguments );
    }
    /**
     * Prunes resolved events only after the application authorizes removal of external references.
     * @returns numeric
     */
    public numeric function pruneResolvedEvents(
        required date eventsBefore,
        required date deliveriesBefore,
        numeric limit = 100,
        any constraints,
        any beforePrune
    ) {
        var values = structCopy( arguments );
        if ( !isNull( arguments.beforePrune ) ) {
            var observer = arguments.beforePrune;
            values.beforePrune = ( event, rows ) => observer(
                newNotificationEvent().configure( event ),
                rows.map( ( row ) => delivery( row ) )
            );
        }
        return variables.deliveryStore.pruneResolvedEvents( argumentCollection = values );
    }

    /**
     * Resolves the current application policy and returns its preparation decision.
     * @returns DeliveryPreparation
     */
    private DeliveryPreparation function checkEligibility(
        required NotificationDelivery work,
        required any notifiable,
        required NotificationEvent event
    ) {
        var policy = variables.runtime.resolve( "eligibilityPolicy" );
        if ( isNull( policy ) ) {
            return newDeliveryPreparation();
        }
        var ready = policy.check( arguments.work, arguments.notifiable, arguments.event );
        if (
            !isInstanceOf( ready, "megaphone.models.Delivery.DeliveryPreparation" ) || !listFind(
                "ready,suppressed,deferred,permanent",
                ready.getStatus()
            )
        ) {
            throw(
                type = "Megaphone.Delivery.InvalidEligibility",
                message = "Eligibility policies must return a supported DeliveryPreparation."
            );
        }
        return ready;
    }

    /**
     * Stores a suppression or deferral decision without starting transport.
     * @returns DeliveryResult
     */
    private DeliveryResult function settlePreparation(
        required NotificationDelivery work,
        required string token,
        required DeliveryPreparation ready,
        required numeric retrySeconds
    ) {
        return settle(
            arguments.work,
            arguments.token,
            newDeliveryResult().configure( {
                "status": arguments.ready.getStatus() == "deferred" ? "retryable" : arguments.ready.getStatus(),
                "reason": arguments.ready.getReason(),
                "retryDate": arguments.ready.getRetryDate()
            } ),
            arguments.retrySeconds
        );
    }

    /**
     * Records a terminal or deferred outcome using the current claim token.
     * @returns DeliveryResult
     */
    private DeliveryResult function settle(
        required NotificationDelivery work,
        required string token,
        required DeliveryResult outcome,
        required numeric retrySeconds
    ) {
        var completed = variables.deliveryStore.complete(
            id = arguments.work.getId(),
            token = arguments.token,
            outcome = arguments.outcome.getStatus(),
            reason = arguments.outcome.getReason(),
            providerReference = arguments.outcome.getProviderReference(),
            retryDate = arguments.outcome.getRetryDate() ?: dateAdd( "s", arguments.retrySeconds, now() )
        );
        return completed ? arguments.outcome : result( "superseded" );
    }

    /**
     * Creates a typed delivery result from a status and reason.
     * @returns DeliveryResult
     */
    private DeliveryResult function result( required string status, string reason = "" ) {
        return newDeliveryResult().configure( { "status": arguments.status, "reason": arguments.reason } );
    }

    /**
     * Converts an internal delivery row to the public delivery object.
     * @returns NotificationDelivery
     */
    private NotificationDelivery function delivery( required struct row ) {
        var values = duplicate( arguments.row );
        values.notifiableType = values.recipientType;
        values.notifiableId = values.recipientId;
        values.channelName = values.channel;
        return newNotificationDelivery().configure( values );
    }

    /**
     * Maps public Notifiable/channel names onto the existing storage column names.
     * @returns struct
     */
    private struct function storageIntent( required struct intent ) {
        var values = duplicate( arguments.intent );
        if ( structKeyExists( values, "notifiableType" ) ) {
            values.recipientType = values.notifiableType;
            structDelete( values, "notifiableType" );
        }
        if ( structKeyExists( values, "notifiableId" ) ) {
            values.recipientId = values.notifiableId;
            structDelete( values, "notifiableId" );
        }
        if ( structKeyExists( values, "channelName" ) ) {
            values.channel = values.channelName;
            structDelete( values, "channelName" );
        }
        return values;
    }

    /**
     * Supplies a fresh DeliveryPreparation using the application's WireBox mapping.
     * @returns DeliveryPreparation
     */
    private DeliveryPreparation function newDeliveryPreparation() provider="DeliveryPreparation@megaphone" {
    }

    /**
     * Supplies a fresh DeliveryRecoveryResult using the application's WireBox mapping.
     * @returns DeliveryRecoveryResult
     */
    private DeliveryRecoveryResult function newDeliveryRecoveryResult() provider="DeliveryRecoveryResult@megaphone" {
    }

    /**
     * Supplies a fresh DeliveryResult using the application's WireBox mapping.
     * @returns DeliveryResult
     */
    private DeliveryResult function newDeliveryResult() provider="DeliveryResult@megaphone" {
    }

    /**
     * Supplies a fresh NotificationDelivery using the application's WireBox mapping.
     * @returns NotificationDelivery
     */
    private NotificationDelivery function newNotificationDelivery() provider="NotificationDelivery@megaphone" {
    }

    /**
     * Supplies a fresh NotificationDeliveryAttempt using the application's WireBox mapping.
     * @returns NotificationDeliveryAttempt
     */
    private NotificationDeliveryAttempt function newNotificationDeliveryAttempt()
        provider="NotificationDeliveryAttempt@megaphone"
    {
    }

    /**
     * Supplies a fresh NotificationDeliveryPage using the application's WireBox mapping.
     * @returns NotificationDeliveryPage
     */
    private NotificationDeliveryPage function newNotificationDeliveryPage() provider="NotificationDeliveryPage@megaphone" {
    }

    /**
     * Supplies a fresh NotificationEvent using the application's WireBox mapping.
     * @returns NotificationEvent
     */
    private NotificationEvent function newNotificationEvent() provider="NotificationEvent@megaphone" {
    }

    /**
     * Supplies a fresh NotificationRecoveryPage using the application's WireBox mapping.
     * @returns NotificationRecoveryPage
     */
    private NotificationRecoveryPage function newNotificationRecoveryPage() provider="NotificationRecoveryPage@megaphone" {
    }

    /**
     * Supplies a fresh NotificationRecoveryReceipt using the application's WireBox mapping.
     * @returns NotificationRecoveryReceipt
     */
    private NotificationRecoveryReceipt function newNotificationRecoveryReceipt()
        provider="NotificationRecoveryReceipt@megaphone"
    {
    }

}
