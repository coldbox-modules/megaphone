/** Public named digest API. Applications own content, consent, eligibility and recipient resolution. */
component singleton {

    property name="store" inject="EmailDigestStore@megaphone";
    property name="calendar" inject="EmailDigestSchedule@megaphone";
    property name="settings" inject="box:moduleSettings:megaphone";
    property name="wirebox" inject="wirebox";
    property name="deliveries" inject="NotificationDeliveryService@megaphone";
    property name="deliveryStore" inject="DeliveryStore@megaphone";
    property name="hasher" inject="NotificationSnapshotHasher@megaphone";

    variables.definitionTimezones = {};

    /**
     * Builds a bounded, stable logical item identity from ordered domain identity parts.
     * @returns string
     */
    public string function itemKey( required array parts ) {
        if ( arguments.parts.isEmpty() ) {
            throw(
                type = "Megaphone.Digests.InvalidItem",
                message = "Provide stable domain identity parts, not a new random value on each retry."
            );
        }
        return variables.hasher.digest( arguments.parts );
    }

    /**
     * Converts the original saved event date to integer UTC epoch milliseconds.
     * @returns numeric
     */
    public numeric function occurredAt( required date occurrence ) {
        return variables.calendar.epoch( arguments.occurrence );
    }

    /**
     * Adds a named definition and registers its task even after application startup.
     * @returns struct
     */
    public struct function registerDigest( required string digestName, required struct definition ) {
        param variables.settings.digests = {};
        if ( structKeyExists( variables.settings.digests, arguments.digestName ) ) {
            throw(
                type = "Megaphone.Digests.DuplicateDefinition",
                message = "A digest name is already registered. Change configured definitions during application reload."
            );
        }
        variables.settings.digests[ arguments.digestName ] = arguments.definition;
        try {
            var configured = getDefinition( arguments.digestName );
            if ( structKeyExists( configured, "schedule" ) ) {
                registerSchedule( configured.name, { "definition": configured.name }, defaultTimezone( configured ) );
            }
            return configured;
        } catch ( any error ) {
            structDelete( variables.settings.digests, arguments.digestName );
            rethrow;
        }
    }

    /**
     * Connects the service to the ColdBox-managed module scheduler.
     */
    public void function useScheduler( required any scheduler ) {
        variables.scheduler = arguments.scheduler;
        for ( var name in variables.settings.digests ?: {} ) {
            var definition = getDefinition( name );
            if ( structKeyExists( definition, "schedule" ) ) {
                registerSchedule( definition.name, { "definition": definition.name }, defaultTimezone( definition ) );
            }
        }
    }

    /**
     * Restores persisted timezone and shortcut variants, including changes made on another node.
     */
    public void function refreshSchedules() {
        if ( structIsEmpty( variables.settings.digests ?: {} ) ) {
            return;
        }
        for ( var group in variables.store.schedules() ) {
            registerSchedule( group.digestName, group.schedule, group.timezone );
        }
    }

    /**
     * Registers one native task per named schedule/timezone combination.
     */
    private void function registerSchedule(
        required string digestName,
        required struct schedule,
        required string timezone
    ) {
        // Standalone use can freeze explicit cutoffs without starting background work.
        if ( isNull( variables.scheduler ) ) {
            return;
        }
        var name = "emailDigest-" & variables.hasher.digest( [ arguments.digestName, arguments.schedule, arguments.timezone ] );
        lock name="megaphone-#variables.scheduler.getName()#-#name#" type="exclusive" timeout="30" {
            if ( variables.scheduler.hasTask( name ) ) {
                return;
            }
            var definition = getDefinition( arguments.digestName );
            var timing = structKeyExists( arguments.schedule, "definition" ) ? definition.schedule : arguments.schedule;
            var configuredDigestName = definition.name;
            var configuredSchedule = arguments.schedule;
            var zone = arguments.timezone;
            var task = variables.scheduler.task( name ).setTimezone( zone );
            try {
                variables.calendar.configureTask( task, timing );
                task.setTimezone( zone )
                    .call( () => {
                        var cutoff = variables.calendar.cutoff( task );
                        // Drain all recipients for this one scheduled boundary in bounded transactions.
                        while (
                            !prepareDigest(
                                configuredDigestName,
                                cutoff,
                                zone,
                                configuredSchedule
                            ).isEmpty()
                        ) {
                        }
                        dispatchDue();
                    } );
                if ( variables.scheduler.hasStarted() ) {
                    var record = variables.scheduler.getTaskRecord( name );
                    record.future = task.start();
                    record.scheduledAt = now();
                }
            } catch ( any error ) {
                variables.scheduler.removeTask( name );
                rethrow;
            }
        }
    }

    /**
     * Keeps executable configuration in named definitions, and JSON-safe overrides in subscriptions.
     * @returns struct
     */
    private struct function scheduleReference( required any schedule, required string digestName ) {
        if ( isStruct( arguments.schedule ) && structKeyExists( arguments.schedule, "definition" ) ) {
            if ( compareNoCase( arguments.schedule.definition, arguments.digestName ) != 0 ) {
                throw(
                    type = "Megaphone.Digests.InvalidSchedule",
                    message = "A subscription can reference only its own named definition."
                );
            }
            return { "definition": arguments.digestName };
        }
        return variables.calendar.normalize( arguments.schedule );
    }

    /**
     * Inherits the module scheduler timezone unless the definition supplies one.
     * @returns string
     */
    private string function defaultTimezone( required struct definition ) {
        if ( structKeyExists( arguments.definition, "timezone" ) ) {
            return arguments.definition.timezone;
        }
        if ( isObject( arguments.definition.schedule ?: "" ) ) {
            return arguments.definition.schedule.getTimezone().getId();
        }
        if ( isCustomFunction( arguments.definition.schedule ?: "" ) && !isNull( variables.scheduler ) ) {
            if ( !structKeyExists( variables.definitionTimezones, arguments.definition.name ) ) {
                var probeName = "emailDigest-timezone-" & createUUID();
                var probe = variables.scheduler.task( probeName );
                try {
                    variables.calendar.configureTask( probe, arguments.definition.schedule );
                    variables.definitionTimezones[ arguments.definition.name ] = probe.getTimezone().getId();
                } finally {
                    variables.scheduler.removeTask( probeName );
                }
            }
            return variables.definitionTimezones[ arguments.definition.name ];
        }
        return isNull( variables.scheduler ) ? createObject( "java", "java.time.ZoneId" ).systemDefault().getId() : variables.scheduler
            .getTimezone()
            .getId();
    }

    /**
     * Supplies recipient reconstruction without eagerly resolving the runtime.
     * @returns any
     */
    private any function newNotificationRuntime() provider="NotificationRuntime@megaphone" {
    }

    /**
     * Returns the configured named definition after validating its required fields.
     * @returns struct
     */
    public struct function getDefinition( required string digestName ) {
        if (
            !reFind( "^[a-zA-Z0-9_-]{1,100}$", arguments.digestName ) || !structKeyExists(
                variables.settings.digests ?: {},
                arguments.digestName
            )
        ) {
            throw(
                type = "Megaphone.Digests.MissingDefinition",
                message = "Configure the named digest before using it."
            );
        }
        var definition = structCopy( variables.settings.digests[ arguments.digestName ] );
        if (
            !len( definition.emailChannel ?: "" ) || !structKeyExists( definition, "policy" ) || !structKeyExists(
                definition,
                "renderer"
            )
        ) {
            throw(
                type = "Megaphone.Digests.InvalidDefinition",
                message = "A digest needs emailChannel, policy and renderer; scheduled digest mode also needs a schedule."
            );
        }
        var requestedName = arguments.digestName;
        definition.name = structKeyArray( variables.settings.digests ).filter( ( key ) => compareNoCase( key, requestedName ) == 0 )[
            1
        ];
        return definition;
    }

    /**
     * Loads the named subscription owned by this Notifiable, or returns null.
     * @returns any
     */
    public any function getSubscription( required any notifiable, required string digestName ) {
        var definition = getDefinition( arguments.digestName );
        return variables.store.forNotifiable(
            definition.name,
            arguments.notifiable.getNotifiableType(),
            normalizedId( toString( arguments.notifiable.getNotifiableId() ) )
        );
    }

    /**
     * Stores a prospective mode and schedule change; identical choices preserve collected work.
     * @returns struct
     */
    public struct function setSubscription(
        required any notifiable,
        required string digestName,
        required string mode,
        string timezone,
        any schedule,
        date clock = now()
    ) {
        if ( !listFind( "off,immediate,digest", arguments.mode ) ) {
            throw( type = "Megaphone.Digests.InvalidMode", message = "Use off, immediate or digest." );
        }
        var definition = getDefinition( arguments.digestName );
        var timing = isNull( arguments.schedule ) ? { "definition": definition.name } : scheduleReference(
            arguments.schedule,
            definition.name
        );
        var zone = variables.calendar.timezone(
            isNull( arguments.timezone ) ? (
                !isNull( arguments.schedule ) && isObject( arguments.schedule ) ? arguments.schedule
                    .getTimezone()
                    .getId() : defaultTimezone( definition )
            ) : arguments.timezone
        );
        var instant = variables.calendar.epoch( arguments.clock );
        if ( arguments.mode == "digest" ) {
            if ( structKeyExists( timing, "definition" ) && !structKeyExists( definition, "schedule" ) ) {
                throw(
                    type = "Megaphone.Digests.InvalidSchedule",
                    message = "Configure a schedule or supply a subscription override for scheduled digest mode."
                );
            }
            registerSchedule( definition.name, timing, zone );
        }
        transaction {
            try {
                var found = ensureSubscription( arguments.notifiable, definition, instant );
                var current = variables.store.subscription( found.id, true );
                if (
                    current.mode == arguments.mode && current.timezone == zone && variables.hasher.digest(
                        current.schedule,
                        {}
                    ) == variables.hasher.digest( timing, {} )
                ) {
                    return current;
                }
                return variables.store.change(
                    current,
                    arguments.mode,
                    timing,
                    zone,
                    instant,
                    instant
                );
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
    }

    /**
     * Turns off this named subscription after the application authorizes the recipient.
     * @returns struct
     */
    public struct function unsubscribe( required any notifiable, required string digestName, date clock = now() ) {
        var current = getSubscription( arguments.notifiable, arguments.digestName );
        return setSubscription(
            notifiable = arguments.notifiable,
            digestName = arguments.digestName,
            mode = "off",
            timezone = isNull( current ) ? "UTC" : current.timezone,
            schedule = isNull( current ) ? { "definition": arguments.digestName } : current.schedule,
            clock = arguments.clock
        );
    }

    /**
     * Stores collection or a suppression tombstone without recording mail acceptance.
     * @returns struct
     */
    public struct function collect(
        required any notifiable,
        required string digestName,
        required string itemKey,
        required struct data,
        required numeric occurredAt,
        boolean enabled = true,
        string eventId = "",
        date clock = now()
    ) {
        if (
            !len( trim( arguments.itemKey ) ) || len( arguments.itemKey ) > 190 || fix( arguments.occurredAt ) != arguments.occurredAt || arguments.occurredAt > variables.calendar.epoch(
                arguments.clock
            )
        ) {
            throw(
                type = "Megaphone.Digests.InvalidItem",
                message = "Provide a bounded stable item key and a persisted occurrence no later than collection."
            );
        }
        var definition = getDefinition( arguments.digestName );
        var item = {
            "itemKey": arguments.itemKey,
            "data": variables.hasher.snapshot( arguments.data ),
            "occurredAt": arguments.occurredAt
        };
        var instant = variables.calendar.epoch( arguments.clock );
        var recipient = arguments.notifiable;
        transaction {
            try {
                var found = ensureSubscription( arguments.notifiable, definition, instant );
                var current = variables.store.subscription( found.id, true );
                var permitted = arguments.enabled && listFind( "digest,immediate", current.mode ) && resolveCollaborator(
                    definition.policy
                ).canCollect( arguments.notifiable, definition, item );
                if ( current.mode == "immediate" ) {
                    assertSharedStorage();
                }
                var collected = variables.store.collect(
                    subscription = current,
                    itemKey = item.itemKey,
                    data = item.data,
                    payloadHash = variables.hasher.digest( item.data, {} ),
                    occurredAt = item.occurredAt,
                    clock = instant,
                    enabled = permitted,
                    eventId = arguments.eventId
                );
                if ( current.mode == "immediate" && collected.created && collected.status == "collected" ) {
                    var batch = variables.store.freeze(
                        current,
                        instant,
                        ( candidates ) => selectItems(
                            recipient,
                            definition,
                            current,
                            candidates
                        ),
                        collected.id
                    );
                    createBatchDelivery( current, batch );
                    return variables.store.collection( collected.id, true );
                }
                return collected;
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
    }

    /**
     * Freezes due membership and persists one durable mail intent per nonempty batch without sending.
     * @returns array
     */
    public array function prepareDigest(
        required string digestName,
        required numeric cutoff,
        string timezone,
        struct schedule,
        numeric limit = 100
    ) {
        assertSharedStorage();
        var definition = getDefinition( arguments.digestName );
        var zone = isNull( arguments.timezone ) ? defaultTimezone( definition ) : arguments.timezone;
        var timing = isNull( arguments.schedule ) ? { "definition": definition.name } : arguments.schedule;
        validateLimit( arguments.limit );
        var batches = [];
        for (
            var candidate in variables.store.due(
                definition.name,
                zone,
                timing,
                arguments.cutoff,
                arguments.limit
            )
        ) {
            transaction {
                try {
                    var current = variables.store.subscription( candidate.id, true );
                    if (
                        current.mode == "digest" && current.lastCutoffAt < arguments.cutoff && current.timezone == zone && variables.hasher.digest(
                            current.schedule
                        ) == variables.hasher.digest( timing )
                    ) {
                        var recipient = newNotificationRuntime().getNotifiable(
                            current.notifiableType,
                            current.notifiableId
                        );
                        var batch = variables.store.freeze(
                            current,
                            arguments.cutoff,
                            ( candidates ) => selectItems(
                                recipient,
                                definition,
                                current,
                                candidates
                            )
                        );
                        createBatchDelivery( current, batch );
                        batches.append( batch );
                    }
                } catch ( any error ) {
                    transactionRollback();
                    rethrow;
                }
            }
        }
        return batches;
    }

    /**
     * Applies the same consent, eligibility and selection rules to scheduled and one-item batches.
     * @returns array
     */
    private array function selectItems(
        any notifiable,
        required struct definition,
        required struct subscription,
        required array candidates
    ) {
        var policy = resolveCollaborator( arguments.definition.policy );
        if (
            isNull( arguments.notifiable ) || arguments.notifiable.getNotifiableType() != arguments.subscription.notifiableType || compare(
                normalizedId( toString( arguments.notifiable.getNotifiableId() ) ),
                arguments.subscription.notifiableId
            ) != 0 || !policy.canSend( arguments.notifiable, arguments.definition, arguments.subscription )
        ) {
            return [];
        }
        var recipient = arguments.notifiable;
        var configuredDefinition = arguments.definition;
        var eligible = arguments.candidates.filter( ( item ) => policy.isEligible( recipient, configuredDefinition, item ) );
        if ( !structKeyExists( configuredDefinition, "selectItems" ) ) {
            return eligible;
        }
        var selector = configuredDefinition.selectItems;
        var selected = isCustomFunction( selector ) ? selector( recipient, configuredDefinition, duplicate( eligible ) ) : resolveCollaborator(
            selector
        ).selectItems( recipient, configuredDefinition, duplicate( eligible ) );
        if ( !isArray( selected ) ) {
            throw(
                type = "Megaphone.Digests.InvalidSelection",
                message = "selectItems must return an array of candidate items."
            );
        }
        var eligibleIds = eligible.map( ( item ) => item.id );
        for ( var item in selected ) {
            if ( !isStruct( item ) || !eligibleIds.find( item.id ?: "" ) ) {
                throw(
                    type = "Megaphone.Digests.InvalidSelection",
                    message = "selectItems cannot reintroduce an ineligible item."
                );
            }
        }
        return selected;
    }

    /**
     * Creates one durable email intent for nonempty membership, without Provider I/O.
     */
    private void function createBatchDelivery( required struct subscription, required struct batch ) {
        if ( arguments.batch.state != "frozen" ) {
            return;
        }
        var event = variables.deliveries.recordEvent(
            namespace = "megaphone.emailDigest",
            eventKey = arguments.batch.id,
            version = 1,
            type = "emailDigestBatch",
            payload = { "batchId": arguments.batch.id },
            payloadHash = arguments.batch.id,
            notificationMapping = "EmailDigestBatchNotification@megaphone"
        );
        var delivery = variables.deliveries.createDelivery(
            event.getId(),
            {
                "notifiableType": arguments.subscription.notifiableType,
                "notifiableId": arguments.subscription.notifiableId,
                "channelName": "emailDigestBatch",
                "enabled": true,
                "routingData": { "batchId": arguments.batch.id },
                "routingHash": arguments.batch.id,
                "availableDate": now()
            }
        );
        variables.store.attachDelivery( arguments.batch.id, delivery.getId() );
        arguments.batch.deliveryId = delivery.getId();
    }

    /**
     * Dispatches pending digest mail using the existing delivery leases.
     * @returns array
     */
    public array function dispatchDue( numeric limit = 100, date clock = now() ) {
        variables.deliveries.recoverExpired(
            limit = arguments.limit,
            constraints = ( builder ) => builder.where( "channel", "emailDigestBatch" )
        );
        var results = [];
        for (
            var work in variables.deliveries.getDueDeliveries(
                limit = arguments.limit,
                constraints = ( builder ) => builder.where( "channel", "emailDigestBatch" )
            )
        ) {
            results.append( { "deliveryId": work.getId(), "result": variables.deliveries.dispatch( work.getId() ) } );
        }
        return results;
    }

    /**
     * Rechecks live consent and eligibility, permanently excluding items that no longer qualify.
     * @returns struct
     */
    public struct function prepareBatch( required any notifiable, required string batchId ) {
        var batch = variables.store.batch( arguments.batchId );
        if ( isNull( batch ) ) {
            return { "status": "suppressed", "reason": "batch-missing" };
        }
        var current = variables.store.subscription( batch.subscriptionId );
        if (
            isNull( current ) || current.notifiableType != arguments.notifiable.getNotifiableType() || compare(
                current.notifiableId,
                normalizedId( toString( arguments.notifiable.getNotifiableId() ) )
            ) != 0
        ) {
            return { "status": "suppressed", "reason": "recipient-mismatch" };
        }
        var definition = getDefinition( current.digestName );
        var policy = resolveCollaborator( definition.policy );
        if (
            batch.state != "frozen" || current.mode != batch.mode || current.generation != batch.generation || !policy.canSend(
                arguments.notifiable,
                definition,
                current
            )
        ) {
            return { "status": "suppressed", "reason": "subscription-or-consent-disabled" };
        }
        var items = [];
        for ( var item in variables.store.items( batch.id ) ) {
            if ( item.state != "batched" ) {
                continue;
            }
            if ( policy.isEligible( arguments.notifiable, definition, item ) ) {
                items.append( item );
            } else {
                variables.store.exclude( item.id );
            }
        }
        return {
            "status": items.isEmpty() ? "suppressed" : "ready",
            "reason": items.isEmpty() ? "empty-batch" : "",
            "batch": batch,
            "subscription": current,
            "definition": definition,
            "items": items
        };
    }

    /**
     * Rechecks prepared membership under the subscription lock and records transport start.
     * @returns DeliveryPreparation
     * @internal
     */
    public DeliveryPreparation function startBatchTransport(
        required any prepared,
        required any work,
        required string token
    ) {
        var original = arguments.prepared.getData();
        var batch = variables.store.batch( original.batchId );
        transaction {
            try {
                variables.store.subscription( batch.subscriptionId, true );
                var current = prepareBatch( original.notifiable, batch.id );
                if ( current.status != "ready" ) {
                    return newDeliveryPreparation().configure( { "status": "suppressed", "reason": current.reason } );
                }
                if ( serializeJSON( current.items.map( ( item ) => item.id ) ) != serializeJSON( original.itemIds ) ) {
                    return newDeliveryPreparation().configure( { "status": "deferred", "reason": "membership-changed-during-render" } );
                }
                return newDeliveryPreparation().configure( {
                    "status": variables.deliveryStore.startTransport( arguments.work.getId(), arguments.token ) ? "ready" : "deferred",
                    "reason": "transport-fence"
                } );
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
    }

    /**
     * Resolves a configured WireBox mapping or returns the supplied component instance.
     * @returns any
     * @internal
     */
    public any function resolveCollaborator( required any configured ) {
        return isSimpleValue( arguments.configured ) ? variables.wirebox.getInstance( arguments.configured ) : arguments.configured;
    }

    /**
     * Rejects cross-datasource batch/event/delivery work before writing any batch.
     */
    private void function assertSharedStorage() {
        var defaultDatasource = getApplicationMetadata().datasource ?: "";
        var configured = [
            variables.store.getQueryOptions(),
            variables.deliveryStore.getQueryOptions(),
            newEventStore().getQueryOptions()
        ];
        var datasources = configured.map( ( options ) => options.datasource ?: defaultDatasource );
        if (
            serializeJSON( datasources[ 1 ] ) != serializeJSON( datasources[ 2 ] ) || serializeJSON( datasources[ 1 ] ) != serializeJSON(
                datasources[ 3 ]
            )
        ) {
            throw(
                type = "Megaphone.Digests.CrossDatasource",
                message = "Digest, event and delivery stores must share a datasource so freezing and delivery creation commit together."
            );
        }
    }

    /**
     * Supplies the event persistence configuration without eagerly resolving the store.
     * @returns any
     */
    private any function newEventStore() provider="EventStore@megaphone" {
    }

    /**
     * Returns the saved collection admissions for a published notification event.
     * @returns array
     */
    public array function getCollectionsForEvent( required string eventId ) {
        return variables.store.collectionsForEvent( arguments.eventId );
    }

    /**
     * Creates an off subscription when none exists without replacing an existing choice.
     * @returns struct
     */
    private struct function ensureSubscription(
        required any notifiable,
        required struct definition,
        required numeric instant
    ) {
        return variables.store.ensure(
            definition.name,
            notifiable.getNotifiableType(),
            normalizedId( toString( notifiable.getNotifiableId() ) ),
            instant,
            { "definition": definition.name },
            defaultTimezone( definition )
        );
    }
    /**
     * Normalizes UUID casing while preserving case-sensitive application identifiers.
     * @returns string
     */
    private string function normalizedId( required string id ) {
        return isValid( "uuid", arguments.id ) ? lCase( arguments.id ) : arguments.id;
    }
    /**
     * Checks that a scheduler batch limit is an integer from 1 to 1000.
     */
    private void function validateLimit( required numeric limit ) {
        if ( arguments.limit < 1 || arguments.limit > 1000 || fix( arguments.limit ) != arguments.limit ) {
            throw( type = "Megaphone.Digests.InvalidLimit", message = "Use a batch limit from 1 to 1000." );
        }
    }
    /**
     * Supplies a fresh DeliveryPreparation through WireBox.
     * @returns DeliveryPreparation
     */
    private DeliveryPreparation function newDeliveryPreparation() provider="DeliveryPreparation@megaphone" {
    }

}
