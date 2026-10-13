/** Public durable-delivery boundary. Storage owns leases; providers own I/O. */
component singleton {

    property name="eventStore" inject="EventStore@megaphone";
    property name="deliveryStore" inject="DeliveryStore@megaphone";
    property name="runtime" inject="NotificationRuntime@megaphone";
    property name="wirebox" inject="wirebox";

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
        return new megaphone.models.NotificationEvent( variables.eventStore.record( argumentCollection = arguments ) );
    }

    public any function getEvent( required string id ) {
        var row = variables.eventStore.find( arguments.id );
        if ( isNull( row ) ) {
            return;
        }
        return new megaphone.models.NotificationEvent( row );
    }

    public any function getDelivery( required string id, boolean lockRow = false ) {
        var row = variables.deliveryStore.find( argumentCollection = arguments );
        if ( isNull( row ) ) {
            return;
        }
        return delivery( row );
    }

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

    public NotificationDelivery function importDelivery( required struct intent, required struct history ) {
        return delivery(
            variables.deliveryStore.importDelivery( storageIntent( arguments.intent ), arguments.history )
        );
    }

    public array function getDeliveriesForEvent( required string eventId ) {
        return variables.deliveryStore.forEvent( arguments.eventId ).map( ( row ) => delivery( row ) );
    }

    public NotificationDeliveryPage function getDeliveries( numeric maxRows = 50, numeric offset = 0, any constraints ) {
        var page = variables.deliveryStore.getPage( argumentCollection = arguments );
        return new megaphone.models.NotificationDeliveryPage(
            page.results.map( ( row ) => delivery( row ) ),
            page.hasMore
        );
    }

    public array function getStateCounts( any constraints ) {
        return variables.deliveryStore
            .stateCounts( argumentCollection = arguments )
            .map( ( row ) => {
                return { "channelName": row.channel, "state": row.state, "total": row.total };
            } );
    }

    public array function getDueDeliveries( numeric limit = 100, date clock = now(), any constraints ) {
        return variables.deliveryStore.due( argumentCollection = arguments ).map( ( row ) => delivery( row ) );
    }

    public array function getAttempts( required string id ) {
        return variables.deliveryStore
            .attempts( arguments.id )
            .map( ( row ) => new megaphone.models.NotificationDeliveryAttempt( row ) );
    }
    public NotificationRecoveryPage function getRecoveryHistory(
        required string id,
        numeric maxRows = 20,
        numeric offset = 0
    ) {
        var page = variables.deliveryStore.recoveryHistory( argumentCollection = arguments );
        return new megaphone.models.NotificationRecoveryPage(
            page.results.map( ( row ) => new megaphone.models.NotificationRecoveryReceipt( row ) ),
            page.hasMore
        );
    }
    public string function getRecoveryVersion( required NotificationDelivery delivery ) {
        return variables.deliveryStore.recoveryVersion( storageIntent( arguments.delivery.getMemento() ) );
    }
    public boolean function canRecover( required NotificationDelivery delivery ) {
        return variables.deliveryStore.canRecover( storageIntent( arguments.delivery.getMemento() ) );
    }

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
            if ( !isInstanceOf( prepared, "megaphone.models.DeliveryPreparation" ) ) {
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
        if ( !variables.deliveryStore.startTransport( work.getId(), claimed.token ) ) {
            return result( "superseded" );
        }
        var outcome = "";
        try {
            outcome = channel.sendDelivery( prepared, work );
            if (
                !isInstanceOf( outcome, "megaphone.models.DeliveryResult" ) || !listFind(
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
                    return new megaphone.models.DeliveryRecoveryResult( { "status": "missing" } );
                }
                var saved = variables.deliveryStore.getRecoveryRequest( arguments.id, arguments.requestKey );
                if ( isNull( saved ) ) {
                    if ( !canRecover( work ) || getRecoveryVersion( work ) != arguments.expectedVersion ) {
                        return new megaphone.models.DeliveryRecoveryResult( { "status": "conflict" } );
                    }
                    var ready = arguments.eligibility( work );
                    if ( !isInstanceOf( ready, "megaphone.models.DeliveryPreparation" ) || ready.getStatus() != "ready" ) {
                        return new megaphone.models.DeliveryRecoveryResult( { "status": "ineligible" } );
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
                return new megaphone.models.DeliveryRecoveryResult( recovery );
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
    }

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

    public numeric function recoverExpired( numeric limit = 100, date clock = now() ) {
        return variables.deliveryStore.recoverExpired( argumentCollection = arguments );
    }
    public numeric function pruneAttempts( required date beforeDate, numeric limit = 200 ) {
        return variables.deliveryStore.pruneAttempts( argumentCollection = arguments );
    }
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
                new megaphone.models.NotificationEvent( event ),
                rows.map( ( row ) => delivery( row ) )
            );
        }
        return variables.deliveryStore.pruneResolvedEvents( argumentCollection = values );
    }

    private DeliveryPreparation function checkEligibility(
        required NotificationDelivery work,
        required any notifiable,
        required NotificationEvent event
    ) {
        var policy = variables.runtime.resolve( "eligibilityPolicy" );
        if ( isNull( policy ) ) {
            return new megaphone.models.DeliveryPreparation();
        }
        var ready = policy.check( arguments.work, arguments.notifiable, arguments.event );
        if (
            !isInstanceOf( ready, "megaphone.models.DeliveryPreparation" ) || !listFind(
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

    private DeliveryResult function settlePreparation(
        required NotificationDelivery work,
        required string token,
        required DeliveryPreparation ready,
        required numeric retrySeconds
    ) {
        return settle(
            arguments.work,
            arguments.token,
            new megaphone.models.DeliveryResult( {
                "status": arguments.ready.getStatus() == "deferred" ? "retryable" : arguments.ready.getStatus(),
                "reason": arguments.ready.getReason(),
                "retryDate": arguments.ready.getRetryDate()
            } ),
            arguments.retrySeconds
        );
    }

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

    private DeliveryResult function result( required string status, string reason = "" ) {
        return new megaphone.models.DeliveryResult( { "status": arguments.status, "reason": arguments.reason } );
    }

    private NotificationDelivery function delivery( required struct row ) {
        var values = duplicate( arguments.row );
        values.notifiableType = values.recipientType;
        values.notifiableId = values.recipientId;
        values.channelName = values.channel;
        return new megaphone.models.NotificationDelivery( values );
    }

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

}
