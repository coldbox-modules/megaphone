/** Generic digest API. The inherited email API remains compatible with 1.2.0. */
component extends="EmailDigestService" singleton {

    /** Create or reactivate; active settings cannot be silently replaced. */
    public struct function addSubscription(
        required any notifiable,
        required string digestName,
        string mode = "digest",
        string timezone,
        any schedule,
        date clock = now()
    ) {
        var configured = subscriptionSettings( argumentCollection = arguments );
        var definition = getDefinition( arguments.digestName );
        var instant = variables.calendar.epoch( arguments.clock );
        transaction {
            try {
                var current = ensureRecord(
                    arguments.notifiable,
                    definition,
                    configured,
                    instant
                );
                if ( current.mode != "off" ) {
                    if ( sameSettings( current, configured ) ) {
                        return current;
                    }
                    throw(
                        type = "Megaphone.Digests.SubscriptionConflict",
                        message = "Use updateSubscription to change an active subscription."
                    );
                }
                return variables.store.transition(
                    current,
                    configured.mode,
                    configured.schedule,
                    configured.timezone,
                    instant,
                    configured.mode
                );
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
    }

    /** Preserve unsent membership while changing timing, without reactivating a stopped subscription. */
    public struct function updateSubscription(
        required any notifiable,
        required string digestName,
        string mode,
        string timezone,
        any schedule,
        date clock = now()
    ) {
        transaction {
            try {
                var current = requireSubscription( arguments.notifiable, arguments.digestName );
                var requested = structCopy( arguments );
                requested.mode = isNull( arguments.mode ) ? ( current.mode == "off" ? current.resumeMode : current.mode ) : arguments.mode;
                requested.timezone = isNull( arguments.timezone ) ? current.timezone : arguments.timezone;
                requested.schedule = isNull( arguments.schedule ) ? current.schedule : arguments.schedule;
                var configured = subscriptionSettings( argumentCollection = requested );
                var actualMode = current.mode == "off" ? "off" : configured.mode;
                if (
                    current.mode == actualMode && current.timezone == configured.timezone && variables.hasher.digest(
                        current.schedule
                    ) == variables.hasher.digest( configured.schedule ) && current.resumeMode == configured.mode
                ) {
                    return current;
                }
                if ( current.mode != "off" && current.mode != configured.mode ) {
                    throw(
                        type = "Megaphone.Digests.SubscriptionConflict",
                        message = "Stop the subscription before changing between scheduled and immediate modes."
                    );
                }
                var preserved = movableItems( current ).movable.map( ( item ) => item.id );
                return variables.store.transition(
                    current,
                    actualMode,
                    configured.schedule,
                    configured.timezone,
                    variables.calendar.epoch( arguments.clock ),
                    configured.mode,
                    preserved
                );
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
    }

    /** Stop future collection and invalidate unstarted batches. Started transport remains auditable. */
    public any function stopSubscription( required any notifiable, required string digestName, date clock = now() ) {
        transaction {
            try {
                var found = getSubscription( arguments.notifiable, arguments.digestName );
                if ( isNull( found ) ) {
                    return;
                }
                var current = variables.store.subscription( found.id, true );
                if ( current.mode == "off" ) {
                    return current;
                }
                return variables.store.transition(
                    current,
                    "off",
                    current.schedule,
                    current.timezone,
                    variables.calendar.epoch( arguments.clock ),
                    current.mode
                );
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
    }

    /** Resume saved settings prospectively; previously suppressed items stay suppressed. */
    public struct function resumeSubscription( required any notifiable, required string digestName, date clock = now() ) {
        transaction {
            try {
                var current = requireSubscription( arguments.notifiable, arguments.digestName );
                if ( current.mode != "off" ) {
                    return current;
                }
                var configured = subscriptionSettings(
                    digestName = current.digestName,
                    mode = current.resumeMode,
                    timezone = current.timezone,
                    schedule = current.schedule
                );
                return variables.store.transition(
                    current,
                    configured.mode,
                    configured.schedule,
                    configured.timezone,
                    variables.calendar.epoch( arguments.clock ),
                    configured.mode
                );
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
    }

    /** Replace a named subscription, explicitly transferring or discarding its pending membership. */
    public struct function transferSubscription(
        required any notifiable,
        required string fromDigest,
        required string toDigest,
        required string pendingItems,
        date clock = now()
    ) {
        if (
            compareNoCase( arguments.fromDigest, arguments.toDigest ) == 0 || !listFind(
                "transfer,discard",
                arguments.pendingItems
            )
        ) {
            throw(
                type = "Megaphone.Digests.InvalidTransfer",
                message = "Choose different digests and pendingItems transfer or discard."
            );
        }
        var sourceDefinition = getDefinition( arguments.fromDigest );
        var destinationDefinition = getDefinition( arguments.toDigest );
        validateStorage();
        var instant = variables.calendar.epoch( arguments.clock );
        transaction {
            try {
                var found = getSubscription( arguments.notifiable, sourceDefinition.name );
                if ( isNull( found ) ) {
                    throw(
                        type = "Megaphone.Digests.SubscriptionMissing",
                        message = "The source subscription does not exist."
                    );
                }
                // Ensure and lock both identities in the same order, including concurrent opposite transfers.
                var ordered = [ sourceDefinition.name, destinationDefinition.name ];
                ordered.sort( "textnocase" );
                var locked = {};
                for ( var name in ordered ) {
                    var existing = getSubscription( arguments.notifiable, name );
                    if ( !isNull( existing ) ) {
                        locked[ name ] = variables.store.subscription( existing.id, true );
                    } else {
                        var configured = subscriptionSettings( digestName = name, mode = "digest" );
                        locked[ name ] = ensureRecord(
                            arguments.notifiable,
                            getDefinition( name ),
                            configured,
                            instant
                        );
                    }
                }
                var source = locked[ sourceDefinition.name ];
                var destination = locked[ destinationDefinition.name ];
                var result = {
                    "source": source,
                    "destination": destination,
                    "transferred": 0,
                    "deduplicated": 0,
                    "suppressed": 0,
                    "nontransferable": 0
                };
                if ( source.mode == "off" && destination.mode != "off" ) {
                    return result;
                }
                var pending = movableItems( source );
                result.nontransferable = pending.nontransferable;
                var policy = resolveCollaborator( destinationDefinition.policy );
                if (
                    arguments.pendingItems == "transfer" && (
                        !isCustomFunction( policy.canTransfer ?: "" ) || !policy.canTransfer(
                            arguments.notifiable,
                            sourceDefinition,
                            destinationDefinition,
                            pending.movable
                        )
                    )
                ) {
                    throw(
                        type = "Megaphone.Digests.IncompatibleTransfer",
                        message = "The destination policy must explicitly approve the transferred item format."
                    );
                }
                if ( destination.mode == "off" ) {
                    var configured = subscriptionSettings(
                        digestName = destination.digestName,
                        mode = destination.resumeMode,
                        timezone = destination.timezone,
                        schedule = destination.schedule
                    );
                    destination = variables.store.transition(
                        destination,
                        configured.mode,
                        configured.schedule,
                        configured.timezone,
                        instant,
                        configured.mode
                    );
                }
                var transferredIds = [];
                for ( var item in pending.movable ) {
                    if (
                        arguments.pendingItems == "discard" || !policy.canCollect(
                            arguments.notifiable,
                            destinationDefinition,
                            item
                        ) || !policy.isEligible( arguments.notifiable, destinationDefinition, item )
                    ) {
                        result.suppressed++;
                    } else {
                        var received = variables.store.receiveTransfer( destination, item, instant );
                        if ( received.created ) {
                            result.transferred++;
                            transferredIds.append( item.id );
                            if ( destination.mode == "immediate" ) {
                                freezeTransferredImmediate(
                                    arguments.notifiable,
                                    destination,
                                    received.id,
                                    instant
                                );
                            }
                        } else {
                            result.deduplicated++;
                        }
                    }
                }
                result.source = source.mode == "off" ? source : variables.store.transition(
                    source,
                    "off",
                    source.schedule,
                    source.timezone,
                    instant,
                    source.mode
                );
                variables.store.markTransferred( transferredIds );
                result.destination = destination;
                return result;
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
    }

    /** Stable item identities survive source suppression and destination admission. */
    private struct function movableItems( required struct subscription ) {
        var result = { "movable": [], "nontransferable": 0 };
        for ( var item in variables.store.pending( arguments.subscription.id ) ) {
            var started = false;
            if ( len( item.batchId ?: "" ) ) {
                var definition = getDefinition( arguments.subscription.digestName );
                if ( len( definition.notification ?: "" ) ) {
                    var publication = variables.store.publication( item.batchId, true );
                    started = !isNull( publication ) && publication.transportStarted;
                } else {
                    var batch = variables.store.batch( item.batchId );
                    var work = variables.deliveries.getDelivery( batch.deliveryId );
                    started = !isNull( work ) && work.getTransportCount() > 0;
                }
            }
            if ( started ) {
                result.nontransferable++;
            } else {
                result.movable.append( item );
            }
        }
        return result;
    }

    private struct function requireSubscription( required any notifiable, required string digestName ) {
        var current = getSubscription( arguments.notifiable, arguments.digestName );
        if ( isNull( current ) ) {
            throw(
                type = "Megaphone.Digests.SubscriptionMissing",
                message = "Add the subscription before updating or resuming it."
            );
        }
        return variables.store.subscription( current.id, true );
    }

    private struct function ensureRecord(
        required any notifiable,
        required struct definition,
        required struct configured,
        required numeric instant
    ) {
        var recipientId = toString( arguments.notifiable.getNotifiableId() );
        var found = variables.store.ensure(
            arguments.definition.name,
            arguments.notifiable.getNotifiableType(),
            isValid( "uuid", recipientId ) ? lCase( recipientId ) : recipientId,
            arguments.instant,
            arguments.configured.schedule,
            arguments.configured.timezone
        );
        return variables.store.subscription( found.id, true );
    }

    private boolean function sameSettings( required struct current, required struct configured ) {
        return arguments.current.mode == arguments.configured.mode && arguments.current.timezone == arguments.configured.timezone && variables.hasher.digest(
            arguments.current.schedule
        ) == variables.hasher.digest( arguments.configured.schedule );
    }

}
