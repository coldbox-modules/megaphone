/** One durable owner per event/recipient/channel/device. Never performs provider I/O. */
component accessors="true" {

    property name="properties";

    function init( struct properties = {} ) {
        variables.properties = arguments.properties;
        return this;
    }

    public struct function enqueue(
        required string eventId,
        required string recipientType,
        required string recipientId,
        required string channel,
        required struct routingData,
        required string routingHash,
        string deviceId = "",
        string initialState = "queued",
        date availableDate = now()
    ) {
        if (
            !len( trim( arguments.eventId ) ) || !len( trim( arguments.recipientType ) ) ||
            !len( trim( arguments.recipientId ) ) || !len( trim( arguments.channel ) ) ||
            !len( trim( arguments.routingHash ) ) || !listFind( "queued,suppressed", arguments.initialState )
        ) {
            throw(
                type = "Megaphone.Delivery.InvalidIntent",
                message = "A delivery requires a complete identity, routing hash, and queued or suppressed state."
            );
        }
        var identity = {
            "eventId": arguments.eventId,
            "recipientType": arguments.recipientType,
            "recipientId": arguments.recipientId,
            "channel": arguments.channel,
            "deviceId": arguments.deviceId
        };
        var values = duplicate( identity );
        values.deviceId = textBinding( identity.deviceId );
        values.append( {
            "id": uuid(),
            "routingHash": arguments.routingHash,
            "routingData": serializeJSON( arguments.routingData ),
            "state": arguments.initialState,
            "attemptCount": 0,
            "availableDate": arguments.availableDate,
            "createdDate": now(),
            "updatedDate": now(),
            "settledDate": timestamp( arguments.initialState == "suppressed" ? now() : javacast( "null", "" ) )
        } );
        newDeliveryQuery().insertIgnore( values );
        var stored = newDeliveryQuery()
            .where( "eventId", identity.eventId )
            .where( "recipientType", identity.recipientType )
            .where( "recipientId", identity.recipientId )
            .where( "channel", identity.channel )
            .where( "deviceId", textBinding( identity.deviceId ) )
            .get()[ 1 ];
        if ( stored.routingHash != arguments.routingHash ) {
            throw(
                type = "Megaphone.Delivery.IdentityConflict",
                message = "This delivery identity already refers to different routing content."
            );
        }
        var result = decode( stored );
        result[ "created" ] = stored.id == values.id;
        return result;
    }

    /** Trusted migration boundary. Restores storage state without routing, claims, or provider I/O. */
    public struct function importDelivery( required struct intent, required struct history ) {
        var state = arguments.history.state ?: "";
        var attemptCount = arguments.history.attemptCount ?: 0;
        var reference = arguments.history.providerReference ?: "";
        var reason = arguments.history.reason ?: "";
        if (
            !listFind( "queued,retryable,accepted,suppressed,permanent,ambiguous", state ) ||
            !isNumeric( attemptCount ) || attemptCount < 0 || fix( attemptCount ) != attemptCount ||
            !isDate( arguments.history.createdDate ?: "" ) || len( reference ) > 190 || len( reason ) > 190 ||
            ( state == "accepted" && !len( trim( reference ) ) ) ||
            ( !isNull( arguments.history.settledDate ) && !isDate( arguments.history.settledDate ) )
        ) {
            throw(
                type = "Megaphone.Delivery.InvalidImport",
                message = "Imported work requires valid state, dates, attempts and bounded acceptance evidence."
            );
        }
        transaction {
            var values = duplicate( arguments.intent );
            values.initialState = "queued";
            var work = enqueue( argumentCollection = values );
            if ( !work.created ) {
                return work;
            }
            var terminal = listFind( "accepted,suppressed,permanent", state ) > 0;
            newDeliveryQuery()
                .where( "id", work.id )
                .update( {
                    "state": state,
                    "attemptCount": attemptCount,
                    "providerReference": textBinding( reference ),
                    "reason": textBinding( reason ),
                    "createdDate": arguments.history.createdDate,
                    "settledDate": timestamp(
                        terminal ? ( arguments.history.settledDate ?: now() ) : javacast( "null", "" )
                    )
                } );
            var result = this.find( work.id );
            result.created = true;
            return result;
        }
    }

    /** lockRow requires the consumer's transaction and protects external lifecycle work. */
    public any function find( required string id, boolean lockRow = false ) {
        var query = newDeliveryQuery().where( "id", arguments.id );
        if ( arguments.lockRow ) {
            query.lockForUpdate();
        }
        var rows = query.get();
        if ( rows.isEmpty() ) {
            return;
        }
        return decode( rows[ 1 ] );
    }

    /** Trusted backend listing. Application constraints run before stable ordering and pagination. */
    public struct function getPage( numeric maxRows = 50, numeric offset = 0, any constraints ) {
        var size = max( 1, min( 200, fix( arguments.maxRows ) ) );
        var query = newDeliveryQuery()
            .from( ( variables.properties.table ?: "megaphone_deliveries" ) & " AS delivery" )
            .select( "delivery.*" );
        if ( !isNull( arguments.constraints ) ) {
            arguments.constraints( query );
        }
        var rows = query
            .clearOrders()
            .orderBy( "delivery.updatedDate", "desc" )
            .orderBy( "delivery.id" )
            .limit( size + 1 )
            .offset( max( 0, fix( arguments.offset ) ) )
            .get();
        var more = rows.len() > size;
        if ( more ) {
            rows.deleteAt( size + 1 );
        }
        return { results: rows.map( ( row ) => decode( row ) ), hasMore: more };
    }

    /** Trusted backend reconciliation: filters apply before aggregate counts. */
    public array function stateCounts( any constraints ) {
        var query = newDeliveryQuery().from( ( variables.properties.table ?: "megaphone_deliveries" ) & " AS delivery" );
        if ( !isNull( arguments.constraints ) ) {
            arguments.constraints( query );
        }
        return query
            .select( [ "delivery.channel", "delivery.state" ] )
            .selectRaw( "COUNT(DISTINCT delivery.id) AS total" )
            .groupBy( [ "delivery.channel", "delivery.state" ] )
            .orderBy( "delivery.channel" )
            .orderBy( "delivery.state" )
            .get();
    }

    public array function forEvent( required string eventId ) {
        return newDeliveryQuery()
            .where( "eventId", arguments.eventId )
            .orderBy( "id" )
            .get()
            .map( ( row ) => decode( row ) );
    }

    /** Current-state token for explicit, optimistic operator commands. */
    public string function recoveryVersion( required struct delivery ) {
        return lCase(
            hash(
                serializeJSON( [
                    arguments.delivery.id,
                    arguments.delivery.state,
                    arguments.delivery.attemptCount,
                    arguments.delivery.transportCount,
                    arguments.delivery.updatedDate,
                    arguments.delivery.providerReference
                ] ),
                "SHA-256"
            )
        );
    }

    public boolean function canRecover( required struct delivery ) {
        return listFind( "retryable,permanent", arguments.delivery.state ) > 0 && arguments.delivery.recoveryAllowance < 45;
    }

    /** Caller supplies operator authorization and live eligibility. No provider I/O occurs here. */
    public struct function requestRecovery(
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
        if (
            !len( trim( arguments.requestKey ) ) || len( arguments.requestKey ) > 128 ||
            !len( trim( arguments.actorId ) ) || len( arguments.actorId ) > 190 || len( arguments.actorLabel ) > 190 ||
            !reFind( "^[a-f0-9]{64}$", arguments.expectedVersion ) || arguments.additionalAttempts < 1 ||
            arguments.additionalAttempts > 5 || fix( arguments.additionalAttempts ) != arguments.additionalAttempts
        ) {
            throw(
                type = "Megaphone.Delivery.InvalidRecovery",
                message = "Recovery requires a bounded identity, current version and 1-5 additional attempts."
            );
        }
        transaction {
            var rows = newDeliveryQuery()
                .where( "id", arguments.id )
                .lockForUpdate()
                .get();
            if ( rows.isEmpty() ) {
                return { status: "missing" };
            }
            var row = rows[ 1 ];
            var intentHash = lCase(
                hash(
                    serializeJSON( [
                        arguments.id,
                        arguments.actorId,
                        arguments.expectedVersion,
                        arguments.additionalAttempts
                    ] ),
                    "SHA-256"
                )
            );
            var saved = newRecoveryQuery()
                .where( "deliveryId", arguments.id )
                .where( "requestKey", arguments.requestKey )
                .get();
            if ( !saved.isEmpty() ) {
                return saved[ 1 ].intentHash == intentHash ? {
                    status: "saved",
                    replayed: true,
                    receipt: saved[ 1 ],
                    delivery: this.find( arguments.id )
                } : { status: "conflict" };
            }
            if (
                !canRecover( decode( row ) ) || recoveryVersion( decode( row ) ) != arguments.expectedVersion ||
                row.recoveryAllowance + arguments.additionalAttempts > 45
            ) {
                return { status: "conflict" };
            }
            var ready = arguments.eligibility( decode( row ) );
            if ( !isStruct( ready ) || ( ready.status ?: "" ) != "ready" ) {
                return { status: "ineligible" };
            }
            var receipt = {
                "id": uuid(),
                "deliveryId": row.id,
                "requestKey": arguments.requestKey,
                "intentHash": intentHash,
                "actorId": arguments.actorId,
                "actorLabel": textBinding( arguments.actorLabel ),
                "priorState": row.state,
                "priorAttemptCount": row.attemptCount,
                "priorTransportCount": row.transportCount,
                "priorReason": textBinding( row.reason ),
                "priorProviderReference": textBinding( row.providerReference ),
                "additionalAttempts": arguments.additionalAttempts,
                "createdDate": arguments.clock
            };
            newRecoveryQuery().insert( receipt );
            var available = dateCompare( row.availableDate, arguments.clock ) > 0 ? row.availableDate : arguments.clock;
            newDeliveryQuery()
                .where( "id", row.id )
                .update( {
                    "state": "queued",
                    "recoveryAllowance": row.recoveryAllowance + arguments.additionalAttempts,
                    "availableDate": available,
                    "updatedDate": arguments.clock,
                    "reason": textBinding( "operator-recovery" ),
                    "leaseToken": textBinding( "" ),
                    "leaseUntil": timestamp(),
                    "transportStartedDate": timestamp(),
                    "settledDate": timestamp()
                } );
            var work = this.find( row.id );
            arguments.queueAdapter.enqueue( work );
            return {
                status: "saved",
                replayed: false,
                receipt: newRecoveryQuery().where( "id", receipt.id ).get()[ 1 ],
                delivery: work
            };
        }
    }

    public struct function recoveryHistory( required string id, numeric maxRows = 20, numeric offset = 0 ) {
        var size = max( 1, min( 200, fix( arguments.maxRows ) ) );
        var rows = newRecoveryQuery()
            .where( "deliveryId", arguments.id )
            .orderBy( "createdDate", "desc" )
            .orderBy( "id", "desc" )
            .limit( size + 1 )
            .offset( max( 0, fix( arguments.offset ) ) )
            .get();
        var more = rows.len() > size;
        if ( more ) {
            rows.deleteAt( size + 1 );
        }
        return { results: rows, hasMore: more };
    }

    private any function newRecoveryQuery() {
        return newQueryBuilder()
            .from( variables.properties.recoveriesTable ?: "megaphone_delivery_recoveries" )
            .mergeDefaultOptions( variables.properties.queryOptions ?: {} );
    }

    /** Claim and attempt creation commit before provider I/O. Duplicate jobs cannot share a lease. */
    public struct function claim(
        required string id,
        numeric leaseSeconds = 60,
        numeric maxAttempts = 5,
        date clock = now()
    ) {
        if (
            arguments.leaseSeconds < 1 || fix( arguments.leaseSeconds ) != arguments.leaseSeconds ||
            arguments.maxAttempts < 1 || fix( arguments.maxAttempts ) != arguments.maxAttempts
        ) {
            throw(
                type = "Megaphone.Delivery.InvalidLease",
                message = "Lease duration and attempt limit must be positive integers."
            );
        }
        transaction {
            var rows = newDeliveryQuery()
                .where( "id", arguments.id )
                .lockForUpdate()
                .get();
            if ( rows.isEmpty() ) {
                return { "status": "missing" };
            }
            var row = rows[ 1 ];
            if ( row.state == "processing" ) {
                if ( dateCompare( row.leaseUntil, arguments.clock ) > 0 ) {
                    return { "status": "busy" };
                }
                var outcome = isDate( row.transportStartedDate ) ? "ambiguous" : "retryable";
                settle(
                    row,
                    outcome,
                    "lease-expired",
                    "",
                    arguments.clock,
                    arguments.clock
                );
                row.state = outcome;
                row.availableDate = arguments.clock;
            }
            if ( !listFind( "queued,retryable", row.state ) ) {
                return { "status": row.state };
            }
            if ( dateCompare( row.availableDate, arguments.clock ) > 0 ) {
                return { "status": "deferred" };
            }
            if ( row.transportCount >= arguments.maxAttempts + row.recoveryAllowance ) {
                newDeliveryQuery()
                    .where( "id", row.id )
                    .update( {
                        "state": "permanent",
                        "reason": "attempt-limit",
                        "settledDate": timestamp( arguments.clock ),
                        "updatedDate": arguments.clock
                    } );
                return { "status": "exhausted" };
            }
            var token = uuid();
            var number = row.attemptCount + 1;
            newDeliveryQuery()
                .where( "id", row.id )
                .update( {
                    "state": "processing",
                    "attemptCount": number,
                    "leaseToken": token,
                    "leaseUntil": timestamp( dateAdd( "s", arguments.leaseSeconds, arguments.clock ) ),
                    "transportStartedDate": timestamp(),
                    "settledDate": timestamp(),
                    "reason": textBinding( "" ),
                    "updatedDate": arguments.clock
                } );
            newAttemptQuery().insert( {
                "id": uuid(),
                "deliveryId": row.id,
                "number": number,
                "leaseToken": token,
                "outcome": "claimed",
                "startedDate": arguments.clock
            } );
            return { "status": "ready", "delivery": this.find( row.id ), "token": token };
        }
    }

    /** Must succeed immediately before external I/O; an expired or superseded worker cannot start transport. */
    public boolean function startTransport( required string id, required string token, date clock = now() ) {
        transaction {
            var rows = newDeliveryQuery()
                .where( "id", arguments.id )
                .lockForUpdate()
                .get();
            if ( rows.isEmpty() ) {
                return false;
            }
            var row = rows[ 1 ];
            if (
                row.state != "processing" || row.leaseToken != arguments.token ||
                dateCompare( row.leaseUntil, arguments.clock ) <= 0 || isDate( row.transportStartedDate )
            ) {
                return false;
            }
            newDeliveryQuery()
                .where( "id", row.id )
                .update( {
                    "transportStartedDate": timestamp( arguments.clock ),
                    "transportCount": row.transportCount + 1,
                    "updatedDate": arguments.clock
                } );
            newAttemptQuery()
                .where( "deliveryId", row.id )
                .where( "leaseToken", arguments.token )
                .update( { "outcome": "sending", "transportStartedDate": timestamp( arguments.clock ) } );
            return true;
        }
    }

    /** Late acceptance may settle the same ambiguous lease, but never a replacement attempt. */
    public boolean function complete(
        required string id,
        required string token,
        required string outcome,
        string reason = "",
        string providerReference = "",
        date retryDate = now(),
        date clock = now()
    ) {
        if ( !listFind( "accepted,suppressed,retryable,permanent,ambiguous", arguments.outcome ) ) {
            throw( type = "Megaphone.Delivery.InvalidOutcome", message = "Unknown provider outcome." );
        }
        transaction {
            var rows = newDeliveryQuery()
                .where( "id", arguments.id )
                .lockForUpdate()
                .get();
            if ( rows.isEmpty() ) {
                return false;
            }
            var row = rows[ 1 ];
            if ( row.leaseToken != arguments.token || !listFind( "processing,ambiguous", row.state ) ) {
                return false;
            }
            if ( arguments.outcome == "accepted" && !isDate( row.transportStartedDate ) ) {
                throw(
                    type = "Megaphone.Delivery.TransportNotStarted",
                    message = "Acceptance requires a recorded transport start."
                );
            }
            if ( arguments.outcome == "suppressed" && isDate( row.transportStartedDate ) ) {
                throw(
                    type = "Megaphone.Delivery.TransportAlreadyStarted",
                    message = "Started transport cannot be treated as suppressed."
                );
            }
            settle(
                row,
                arguments.outcome,
                arguments.reason,
                arguments.providerReference,
                arguments.retryDate,
                arguments.clock
            );
            return true;
        }
    }

    /** Verified receipts may originate from an older attempt or a previous delivery owner during migration. */
    public boolean function reconcileAccepted( required string id, required function acceptance, date clock = now() ) {
        transaction {
            var rows = newDeliveryQuery()
                .where( "id", arguments.id )
                .lockForUpdate()
                .get();
            if ( rows.isEmpty() ) {
                return false;
            }
            var row = rows[ 1 ];
            if ( row.state == "accepted" ) {
                return true;
            }
            // The consumer validates an authoritative receipt for this immutable delivery identity.
            // This callback must perform local checks only, never provider I/O.
            var receipt = arguments.acceptance( decode( row ) );
            if ( !isStruct( receipt ) || !isBoolean( receipt.accepted ?: "" ) ) {
                throw(
                    type = "Megaphone.Delivery.InvalidReceipt",
                    message = "Receipt validation requires an explicit acceptance decision."
                );
            }
            if ( !receipt.accepted ) {
                return false;
            }
            if (
                !isSimpleValue( receipt.providerReference ?: "" ) || !len( trim( receipt.providerReference ?: "" ) ) || len(
                    receipt.providerReference
                ) > 190
            ) {
                throw(
                    type = "Megaphone.Delivery.InvalidReceipt",
                    message = "Verified acceptance requires a bounded provider reference."
                );
            }
            newDeliveryQuery()
                .where( "id", arguments.id )
                .update( {
                    "state": "accepted",
                    "reason": textBinding( "receipt-confirmed" ),
                    "providerReference": textBinding( receipt.providerReference ),
                    "updatedDate": arguments.clock,
                    "settledDate": timestamp( arguments.clock )
                } );
            // Preserve attempt outcomes: the receipt can describe an older attempt or an imported owner.
            // A currently running attempt can no longer start transport or overwrite this receipt.
            return true;
        }
    }

    /** Due rows are durable scheduling input; duplicate scheduler jobs are fenced by claim(). */
    public array function due( numeric limit = 100, date clock = now(), any constraints ) {
        if ( arguments.limit < 1 || fix( arguments.limit ) != arguments.limit ) {
            throw( type = "Megaphone.Delivery.InvalidBatch", message = "Batch size must be a positive integer." );
        }
        var query = newDeliveryQuery();
        if ( !isNull( arguments.constraints ) ) {
            arguments.constraints( query );
        }
        return query
            .whereIn( "state", [ "queued", "retryable" ] )
            .where( "availableDate", "<=", arguments.clock )
            .orderBy( "availableDate" )
            .orderBy( "id" )
            .limit( arguments.limit )
            .get()
            .map( ( row ) => decode( row ) );
    }

    public array function attempts( required string id ) {
        return newAttemptQuery()
            .where( "deliveryId", arguments.id )
            .orderBy( "number" )
            .get();
    }

    /** Recover lost jobs in bounded batches without retrying uncertain acceptance. */
    public numeric function recoverExpired( numeric limit = 100, date clock = now() ) {
        validateBatch( arguments.limit );
        var candidates = newDeliveryQuery()
            .where( "state", "processing" )
            .where( "leaseUntil", "<=", arguments.clock )
            .orderBy( "leaseUntil" )
            .orderBy( "id" )
            .limit( arguments.limit )
            .get();
        var recovered = 0;
        for ( var candidate in candidates ) {
            transaction {
                var rows = newDeliveryQuery()
                    .where( "id", candidate.id )
                    .lockForUpdate()
                    .get();
                if (
                    rows.isEmpty() || rows[ 1 ].state != "processing" || dateCompare(
                        rows[ 1 ].leaseUntil,
                        arguments.clock
                    ) > 0
                ) {
                    continue;
                }
                var row = rows[ 1 ];
                settle(
                    row,
                    isDate( row.transportStartedDate ) ? "ambiguous" : "retryable",
                    "lease-expired",
                    "",
                    arguments.clock,
                    arguments.clock
                );
                recovered++;
            }
        }
        return recovered;
    }

    /** Terminal diagnostic cleanup retains durable delivery identities and receipts. */
    public numeric function pruneAttempts( required date beforeDate, numeric limit = 200 ) {
        validateBatch( arguments.limit );
        var deliveryTable = variables.properties.table ?: "megaphone_deliveries";
        var attemptsTable = variables.properties.attemptsTable ?: "megaphone_delivery_attempts";
        var candidates = newAttemptQuery()
            .where( "finishedDate", "<", arguments.beforeDate )
            .whereExists( ( query ) => query
                .from( deliveryTable )
                .selectRaw( "1" )
                .whereColumn( deliveryTable & ".id", attemptsTable & ".deliveryId" )
                .whereIn( "state", [ "accepted", "suppressed", "permanent" ] ) )
            .orderBy( "finishedDate" )
            .orderBy( "id" )
            .limit( arguments.limit )
            .get();
        var removed = 0;
        for ( var candidate in candidates ) {
            transaction {
                // Recovery/claim/complete take this same owner lock before state changes.
                var owners = newDeliveryQuery()
                    .where( "id", candidate.deliveryId )
                    .lockForUpdate()
                    .get();
                if ( owners.isEmpty() || !listFind( "accepted,suppressed,permanent", owners[ 1 ].state ) ) {
                    continue;
                }
                var attempt = newAttemptQuery()
                    .where( "id", candidate.id )
                    .where( "finishedDate", "<", arguments.beforeDate )
                    .lockForUpdate()
                    .get();
                if ( !attempt.isEmpty() ) {
                    newAttemptQuery().where( "id", candidate.id ).delete();
                    removed++;
                }
            }
        }
        return removed;
    }

    /** Expire event identities only beyond the application's replay window with no unresolved work. */
    public numeric function pruneResolvedEvents(
        required date eventsBefore,
        required date deliveriesBefore,
        numeric limit = 100,
        any constraints,
        any beforePrune
    ) {
        validateBatch( arguments.limit );
        var eventTable = variables.properties.eventsTable ?: "megaphone_events";
        var deliveryTable = variables.properties.table ?: "megaphone_deliveries";
        var deliveryCutoff = arguments.deliveriesBefore;
        var candidateQuery = newQueryBuilder()
            .from( eventTable )
            .mergeDefaultOptions( variables.properties.queryOptions ?: {} )
            .where( "createdDate", "<", arguments.eventsBefore )
            .whereNotExists( ( query ) => query
                .from( deliveryTable )
                .selectRaw( "1" )
                .whereColumn( deliveryTable & ".eventId", eventTable & ".id" )
                .where( ( unsafe ) => unsafe
                    .whereNotIn( "state", [ "accepted", "suppressed", "permanent" ] )
                    .orWhereNull( "settledDate" )
                    .orWhere( "settledDate", ">=", deliveryCutoff ) ) )
            .orderBy( "createdDate" )
            .orderBy( "id" )
            .limit( arguments.limit );
        if ( !isNull( arguments.constraints ) ) {
            arguments.constraints( candidateQuery );
        }
        var candidates = candidateQuery.get();
        var removed = 0;
        for ( var candidate in candidates ) {
            transaction {
                var events = newQueryBuilder()
                    .from( eventTable )
                    .mergeDefaultOptions( variables.properties.queryOptions ?: {} )
                    .where( "id", candidate.id )
                    .lockForUpdate();
                if ( !isNull( arguments.constraints ) ) {
                    arguments.constraints( events );
                }
                events = events.get();
                if ( events.isEmpty() ) {
                    continue;
                }
                // Lock the parent first: the FK prevents new deliveries racing deletion.
                var deliveries = newDeliveryQuery()
                    .where( "eventId", candidate.id )
                    .orderBy( "id" )
                    .lockForUpdate()
                    .get();
                var unsafe = deliveries.some( ( row ) => !listFind( "accepted,suppressed,permanent", row.state ) ||
                !isDate( row.settledDate ) || dateCompare( row.settledDate, deliveryCutoff ) >= 0 );
                if ( unsafe ) {
                    continue;
                }
                // Trusted consumer evidence is committed atomically with retirement.
                if ( !isNull( arguments.beforePrune ) ) {
                    arguments.beforePrune( duplicate( events[ 1 ] ), duplicate( deliveries ) );
                }
                var ids = deliveries.map( ( row ) => row.id );
                if ( !ids.isEmpty() ) {
                    newRecoveryQuery().whereIn( "deliveryId", ids ).delete();
                    newAttemptQuery().whereIn( "deliveryId", ids ).delete();
                    newDeliveryQuery().whereIn( "id", ids ).delete();
                }
                newQueryBuilder()
                    .from( eventTable )
                    .mergeDefaultOptions( variables.properties.queryOptions ?: {} )
                    .where( "id", candidate.id )
                    .delete();
                removed++;
            }
        }
        return removed;
    }

    private void function validateBatch( required numeric limit ) {
        if ( arguments.limit < 1 || fix( arguments.limit ) != arguments.limit ) {
            throw( type = "Megaphone.Delivery.InvalidBatch", message = "Batch size must be a positive integer." );
        }
    }

    private void function settle(
        required struct row,
        required string outcome,
        required string reason,
        required string providerReference,
        required date retryDate,
        required date clock
    ) {
        var terminal = listFind( "accepted,suppressed,permanent", arguments.outcome ) > 0;
        newDeliveryQuery()
            .where( "id", arguments.row.id )
            .update( {
                "state": arguments.outcome,
                "reason": textBinding( left( arguments.reason, 190 ) ),
                "providerReference": textBinding( left( arguments.providerReference, 190 ) ),
                "updatedDate": arguments.clock,
                "availableDate": arguments.retryDate,
                "settledDate": timestamp( terminal ? arguments.clock : javacast( "null", "" ) )
            } );
        newAttemptQuery()
            .where( "deliveryId", arguments.row.id )
            .where( "leaseToken", arguments.row.leaseToken )
            .update( {
                "outcome": arguments.outcome,
                "reason": textBinding( left( arguments.reason, 190 ) ),
                "providerReference": textBinding( left( arguments.providerReference, 190 ) ),
                "finishedDate": timestamp( arguments.clock )
            } );
    }

    private struct function decode( required struct row ) {
        var decoded = duplicate( arguments.row );
        decoded.routingData = deserializeJSON( decoded.routingData );
        return decoded;
    }
    private struct function timestamp( any value ) {
        return { "value": arguments.value ?: "", "null": isNull( arguments.value ), "cfsqltype": "timestamp" };
    }
    private struct function textBinding( required string value ) {
        return { "value": arguments.value, "null": false, "cfsqltype": "varchar" };
    }
    private string function uuid() {
        return createObject( "java", "java.util.UUID" ).randomUUID().toString();
    }
    private any function newDeliveryQuery() {
        return newQueryBuilder()
            .from( variables.properties.table ?: "megaphone_deliveries" )
            .mergeDefaultOptions( variables.properties.queryOptions ?: {} );
    }
    private any function newAttemptQuery() {
        return newQueryBuilder()
            .from( variables.properties.attemptsTable ?: "megaphone_delivery_attempts" )
            .mergeDefaultOptions( variables.properties.queryOptions ?: {} );
    }
    private any function newQueryBuilder() provider="QueryBuilder@qb" {
    }

}
