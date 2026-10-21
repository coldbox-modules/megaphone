/** Collection storage. Subscription row locks serialize admission, preference changes and batch cutoffs. */
component accessors="true" {

    property name="properties" type="struct" setter="false";
    property name="uuidGenerator" inject="java:java.util.UUID";

    /**
     * Stores the digest persistence configuration.
     * @returns EmailDigestStore
     */
    public EmailDigestStore function init( struct properties = {} ) {
        variables.properties = arguments.properties;
        return this;
    }

    /**
     * Ensures an off subscription exists without changing its established identity or choices.
     * @returns struct
     */
    public struct function ensure(
        required string digestName,
        required string notifiableType,
        required string notifiableId,
        required numeric clock,
        required struct schedule,
        required string timezone
    ) {
        var identity = {
            "digestName": arguments.digestName,
            "notifiableType": arguments.notifiableType,
            "notifiableId": arguments.notifiableId
        };
        var values = duplicate( identity );
        values.append( {
            "id": uuid(),
            "mode": "off",
            "generation": 1,
            "timezone": arguments.timezone,
            "schedule": serializeJSON( arguments.schedule ),
            "effectiveAt": epochBinding( arguments.clock ),
            "lastCutoffAt": epochBinding( arguments.clock )
        } );
        newDigestQuery( "subscriptions" ).insertIgnore( values );
        return decodeSubscription(
            newDigestQuery( "subscriptions" )
                .where( "digestName", identity.digestName )
                .where( "notifiableType", identity.notifiableType )
                .where( "notifiableId", identity.notifiableId )
                .first()
        );
    }

    /**
     * Loads a subscription by ID, optionally locking it in the caller transaction.
     * @returns any
     */
    public any function subscription( required string id, boolean lockRow = false ) {
        var builder = newDigestQuery( "subscriptions" ).where( "id", arguments.id );
        if ( arguments.lockRow ) {
            builder.lockForUpdate();
        }
        var rows = builder.get();
        if ( rows.isEmpty() ) {
            return;
        }
        return decodeSubscription( rows[ 1 ] );
    }

    /**
     * Loads the named subscription for the supplied Notifiable type and ID.
     * @returns any
     */
    public any function forNotifiable(
        required string digestName,
        required string notifiableType,
        required string notifiableId
    ) {
        var rows = newDigestQuery( "subscriptions" )
            .where( "digestName", arguments.digestName )
            .where( "notifiableType", arguments.notifiableType )
            .where( "notifiableId", arguments.notifiableId )
            .get();
        if ( rows.isEmpty() ) {
            return;
        }
        return decodeSubscription( rows[ 1 ] );
    }

    /**
     * Changes the locked subscription generation and suppresses obsolete collected membership.
     * @returns struct
     */
    public struct function change(
        required struct subscription,
        required string mode,
        required struct schedule,
        required string timezone,
        required numeric clock,
        required numeric lastCutoffAt
    ) {
        var row = arguments.subscription;
        newDigestQuery( "subscriptions" )
            .where( "id", row.id )
            .update( {
                "mode": arguments.mode,
                "generation": row.generation + 1,
                "schedule": serializeJSON( arguments.schedule ),
                "timezone": arguments.timezone,
                "effectiveAt": epochBinding( arguments.clock ),
                "lastCutoffAt": epochBinding( arguments.lastCutoffAt )
            } );
        newDigestQuery( "items" )
            .where( "subscriptionId", row.id )
            .whereIn( "state", [ "collected", "batched" ] )
            .update( { "state": "suppressed" } );
        newDigestQuery( "batches" )
            .where( "subscriptionId", row.id )
            .where( "state", "frozen" )
            .update( { "state": "suppressed" } );
        return this.subscription( row.id );
    }

    /**
     * Admits one stable item identity while the caller holds its subscription lock.
     * @returns struct
     */
    public struct function collect(
        required struct subscription,
        required string itemKey,
        required struct data,
        required string payloadHash,
        required numeric occurredAt,
        required numeric clock,
        required boolean enabled,
        string eventId = ""
    ) {
        var rows = newDigestQuery( "items" )
            .where( "subscriptionId", arguments.subscription.id )
            .where( "itemKey", arguments.itemKey )
            .lockForUpdate()
            .get();
        if ( !rows.isEmpty() ) {
            var saved = rows[ 1 ];
            if ( saved.payloadHash != arguments.payloadHash || saved.occurredAt != arguments.occurredAt ) {
                throw(
                    type = "Megaphone.Digests.IdentityConflict",
                    message = "An item key already refers to different content or occurrence."
                );
            }
            associateEvent( saved.id, arguments.eventId );
            return collection( saved.id );
        }
        var state = arguments.enabled && listFind( "digest,immediate", arguments.subscription.mode ) && arguments.occurredAt >= arguments.subscription.effectiveAt ? "collected" : "suppressed";
        var id = uuid();
        newDigestQuery( "items" ).insert( {
            "id": id,
            "subscriptionId": arguments.subscription.id,
            "generation": arguments.subscription.generation,
            "itemKey": arguments.itemKey,
            "data": serializeJSON( arguments.data ),
            "payloadHash": arguments.payloadHash,
            "occurredAt": epochBinding( arguments.occurredAt ),
            "collectedAt": epochBinding( arguments.clock ),
            "state": state,
            "eventId": textBinding( arguments.eventId ),
            "batchId": textBinding( "" )
        } );
        associateEvent( id, arguments.eventId );
        return { "id": id, "status": state, "created": true };
    }

    /**
     * Loads collection identities and states associated with the saved event.
     * @returns array
     */
    public array function collectionsForEvent( required string eventId ) {
        return newQueryBuilder()
            .from( getTableName( "admissions" ) & " as admission" )
            .mergeDefaultOptions( getQueryOptions() )
            .join(
                getTableName( "items" ) & " as item",
                "item.id",
                "=",
                "admission.itemId"
            )
            .where( "admission.eventId", arguments.eventId )
            .select( [ "item.id", "item.state" ] )
            .get()
            .map( ( row ) => {
                return collection( row.id );
            } );
    }

    /**
     * Returns admission state and the linked delivery for a one-item immediate batch.
     * @returns struct
     */
    public struct function collection( required string id, boolean created = false ) {
        var item = newDigestQuery( "items" )
            .where( "id", arguments.id )
            .lockForUpdate()
            .first();
        var result = { "id": item.id, "status": item.state, "created": arguments.created };
        if ( len( item.batchId ?: "" ) ) {
            var batch = this.batch( item.batchId, true );
            if ( batch.mode == "immediate" ) {
                result.batchId = batch.id;
                if ( len( batch.deliveryId ?: "" ) ) {
                    result.deliveryId = batch.deliveryId;
                }
            }
        }
        return result;
    }

    /**
     * Returns persisted active schedule groups for scheduler registration.
     * @returns array
     */
    public array function schedules() {
        return newDigestQuery( "subscriptions" )
            .where( "mode", "digest" )
            .select( [ "digestName", "timezone", "schedule" ] )
            .distinct()
            .get()
            .map( ( row ) => decodeSubscription( row ) );
    }

    /**
     * Selects subscriptions awaiting this scheduled cutoff.
     * @returns array
     */
    public array function due(
        required string digestName,
        required string timezone,
        required struct schedule,
        required numeric cutoff,
        numeric limit = 100
    ) {
        return newDigestQuery( "subscriptions" )
            .where( "mode", "digest" )
            .where( "digestName", arguments.digestName )
            .where( "timezone", arguments.timezone )
            .where( "schedule", serializeJSON( arguments.schedule ) )
            .where( "lastCutoffAt", "<", epochBinding( arguments.cutoff ) )
            .orderBy( "id" )
            .limit( arguments.limit )
            .get()
            .map( ( row ) => decodeSubscription( row ) );
    }

    /**
     * Freezes selected membership and permanently discards all other pre-cutoff candidates.
     * @returns struct
     */
    public struct function freeze(
        required struct subscription,
        required numeric cutoff,
        required any selectItems,
        string itemId = ""
    ) {
        var row = arguments.subscription;
        var id = uuid();
        var builder = newDigestQuery( "items" )
            .where( "subscriptionId", row.id )
            .where( "generation", row.generation )
            .where( "state", "collected" );
        if ( len( arguments.itemId ) ) {
            builder.where( "id", arguments.itemId );
        } else {
            builder.where( "collectedAt", "<", epochBinding( arguments.cutoff ) );
        }
        var candidates = builder
            .orderBy( "occurredAt", "desc" )
            .orderBy( "itemKey" )
            .lockForUpdate()
            .get()
            .map( ( item ) => {
                item.data = deserializeJSON( item.data );
                return item;
            } );
        var selected = arguments.selectItems( candidates );
        var available = {};
        var ids = [];
        for ( var item in candidates ) {
            available[ item.id ] = true;
        }
        for ( var item in selected ) {
            if ( !isStruct( item ) || !structKeyExists( available, item.id ?: "" ) || ids.find( item.id ) ) {
                throw(
                    type = "Megaphone.Digests.InvalidSelection",
                    message = "Return each selected candidate once; foreign or duplicate items are invalid."
                );
            }
            ids.append( item.id );
        }
        newDigestQuery( "batches" ).insert( {
            "id": id,
            "subscriptionId": row.id,
            "generation": row.generation,
            "cutoffAt": epochBinding( arguments.cutoff ),
            "mode": row.mode,
            "batchKey": len( arguments.itemId ) ? "item:" & arguments.itemId : "cutoff:" & arguments.cutoff,
            "state": ids.isEmpty() ? "empty" : "frozen",
            "deliveryId": textBinding( "" )
        } );
        var discarded = candidates.filter( ( item ) => !ids.find( item.id ) ).map( ( item ) => item.id );
        if ( !discarded.isEmpty() ) {
            newDigestQuery( "items" ).whereIn( "id", discarded ).update( { "state": "discarded", "data": "{}" } );
        }
        for ( var position = 1; position <= ids.len(); position++ ) {
            newDigestQuery( "items" )
                .where( "id", ids[ position ] )
                .update( { "batchId": id, "batchPosition": position, "state": "batched" } );
        }
        if ( !len( arguments.itemId ) ) {
            newDigestQuery( "subscriptions" )
                .where( "id", row.id )
                .update( { "lastCutoffAt": epochBinding( arguments.cutoff ) } );
        }
        return batch( id );
    }

    /**
     * Loads an immutable batch reference by ID, or returns null.
     * @returns any
     */
    public any function batch( required string id, boolean lockRow = false ) {
        var builder = newDigestQuery( "batches" ).where( "id", arguments.id );
        if ( arguments.lockRow ) {
            builder.lockForUpdate();
        }
        var rows = builder.get();
        if ( rows.isEmpty() ) {
            return;
        }
        return rows[ 1 ];
    }

    /**
     * Associates the frozen batch with its durable mail delivery identity.
     */
    public void function attachDelivery( required string id, required string deliveryId ) {
        newDigestQuery( "batches" ).where( "id", arguments.id ).update( { "deliveryId": arguments.deliveryId } );
    }

    /**
     * Loads the original ordered batch membership and restores item data.
     * @returns array
     */
    public array function items( required string batchId, boolean lockRows = false ) {
        var query = newDigestQuery( "items" )
            .where( "batchId", arguments.batchId )
            .orderBy( "batchPosition" )
            .orderBy( "id" );
        if ( arguments.lockRows ) {
            query.lockForUpdate();
        }
        return query
            .get()
            .map( ( item ) => {
                item.data = deserializeJSON( item.data );
                return item;
            } );
    }

    /**
     * Permanently excludes an ineligible item from its frozen batch.
     */
    public void function exclude( required string id ) {
        newDigestQuery( "items" )
            .where( "id", arguments.id )
            .where( "state", "batched" )
            .update( { "state": "suppressed" } );
    }

    /** Generic publication provenance is separate from legacy batches and their delivery IDs. */
    public any function publication( required string batchId, boolean lockRow = false ) {
        var query = newDigestQuery( "publications" ).where( "batchId", arguments.batchId );
        if ( arguments.lockRow ) {
            query.lockForUpdate();
        }
        var rows = query.get();
        if ( !rows.isEmpty() ) {
            return rows[ 1 ];
        }
    }

    public any function publicationForEvent( required string eventId ) {
        var rows = newDigestQuery( "publications" ).where( "eventId", arguments.eventId ).get();
        if ( !rows.isEmpty() ) {
            return rows[ 1 ];
        }
    }

    public void function reservePublication( required string batchId ) {
        newDigestQuery( "publications" ).insert( {
            "batchId": arguments.batchId,
            "eventId": textBinding( "" ),
            "transportStarted": { "value": false, "cfsqltype": "bit" }
        } );
    }

    public void function recordPublication( required string batchId, required string eventId ) {
        newDigestQuery( "publications" )
            .where( "batchId", arguments.batchId )
            .update( { "eventId": arguments.eventId } );
    }

    public void function markPublicationStarted( required string batchId ) {
        newDigestQuery( "publications" )
            .where( "batchId", arguments.batchId )
            .update( { "transportStarted": { "value": true, "cfsqltype": "bit" } } );
    }

    /** Locks all pending source membership after the subscription lock has been acquired. */
    public array function pending( required string subscriptionId ) {
        return newDigestQuery( "items" )
            .where( "subscriptionId", arguments.subscriptionId )
            .whereIn( "state", [ "collected", "batched" ] )
            .orderBy( "id" )
            .lockForUpdate()
            .get()
            .map( ( item ) => {
                item.data = deserializeJSON( item.data );
                return item;
            } );
    }

    /** Starts a new generation without reviving previously suppressed identities. */
    public struct function transition(
        required struct subscription,
        required string mode,
        required struct schedule,
        required string timezone,
        required numeric clock,
        required string resumeMode,
        array preserveIds = []
    ) {
        var current = change(
            arguments.subscription,
            arguments.mode,
            arguments.schedule,
            arguments.timezone,
            arguments.clock,
            arguments.clock
        );
        newDigestQuery( "subscriptions" ).where( "id", current.id ).update( { "resumeMode": arguments.resumeMode } );
        if ( !arguments.preserveIds.isEmpty() ) {
            newDigestQuery( "items" )
                .where( "subscriptionId", current.id )
                .whereIn( "id", arguments.preserveIds )
                .update( {
                    "generation": current.generation,
                    "state": "collected",
                    "batchId": textBinding( "" ),
                    "batchPosition": { "value": 0, "null": true, "cfsqltype": "integer" }
                } );
        }
        return this.subscription( current.id );
    }

    /** Transfer admission bypasses the prospective occurrence boundary, never the destination identity fence. */
    public struct function receiveTransfer( required struct subscription, required struct item, required numeric clock ) {
        var rows = newDigestQuery( "items" )
            .where( "subscriptionId", arguments.subscription.id )
            .where( "itemKey", arguments.item.itemKey )
            .lockForUpdate()
            .get();
        if ( !rows.isEmpty() ) {
            if ( rows[ 1 ].payloadHash != arguments.item.payloadHash || rows[ 1 ].occurredAt != arguments.item.occurredAt ) {
                throw(
                    type = "Megaphone.Digests.IdentityConflict",
                    message = "The destination already has different content for this item key."
                );
            }
            copyAdmissions( arguments.item.id, rows[ 1 ].id );
            // A transfer tombstone is distinct from suppression: explicit transfer back may restore it.
            if ( rows[ 1 ].state == "transferred" ) {
                newDigestQuery( "items" )
                    .where( "id", rows[ 1 ].id )
                    .update( {
                        "generation": arguments.subscription.generation,
                        "state": "collected",
                        "collectedAt": epochBinding( arguments.clock ),
                        "batchId": textBinding( "" ),
                        "batchPosition": { "value": 0, "null": true, "cfsqltype": "integer" }
                    } );
                return { "id": rows[ 1 ].id, "created": true };
            }
            return { "id": rows[ 1 ].id, "created": false };
        }
        var values = duplicate( arguments.item );
        values.id = uuid();
        values.subscriptionId = arguments.subscription.id;
        values.generation = arguments.subscription.generation;
        values.data = serializeJSON( values.data );
        values.occurredAt = epochBinding( values.occurredAt );
        values.collectedAt = epochBinding( arguments.clock );
        values.state = "collected";
        values.eventId = textBinding( values.eventId ?: "" );
        values.batchId = textBinding( "" );
        values.batchPosition = { "value": 0, "null": true, "cfsqltype": "integer" };
        newDigestQuery( "items" ).insert( values );
        copyAdmissions( arguments.item.id, values.id );
        return { "id": values.id, "created": true };
    }

    public void function markTransferred( required array ids ) {
        if ( !arguments.ids.isEmpty() ) {
            newDigestQuery( "items" ).whereIn( "id", arguments.ids ).update( { "state": "transferred" } );
        }
    }

    private void function copyAdmissions( required string sourceId, required string destinationId ) {
        for ( var admission in newDigestQuery( "admissions" ).where( "itemId", arguments.sourceId ).get() ) {
            associateEvent( arguments.destinationId, admission.eventId );
        }
    }

    /**
     * Returns query options with an explicitly configured datasource taking precedence.
     * @returns struct
     */
    public struct function getQueryOptions() {
        var options = duplicate( variables.properties.queryOptions ?: {} );
        if ( structKeyExists( variables.properties, "datasource" ) ) {
            options.datasource = variables.properties.datasource;
        }
        return options;
    }

    /**
     * Builds a query for one configured digest table.
     * @returns any
     */
    private any function newDigestQuery( required string kind ) {
        return newQueryBuilder().from( getTableName( arguments.kind ) ).mergeDefaultOptions( getQueryOptions() );
    }
    /**
     * Returns the configured digest table name, defaulting to the subscriptions table.
     * @returns string
     */
    public string function getTableName( string kind = "subscriptions" ) {
        if ( arguments.kind == "subscriptions" ) {
            return variables.properties.table ?: "megaphone_digest_subscriptions";
        }
        return variables.properties[ arguments.kind & "Table" ] ?: "megaphone_digest_" & arguments.kind;
    }
    /**
     * Records an event admission without creating a second collected item.
     */
    private void function associateEvent( required string itemId, required string eventId ) {
        if ( len( arguments.eventId ) ) {
            newDigestQuery( "admissions" ).insertIgnore( { "eventId": arguments.eventId, "itemId": arguments.itemId } );
        }
    }
    /**
     * Restores the persisted calendar schedule on a subscription row.
     * @returns struct
     */
    private struct function decodeSubscription( required struct row ) {
        arguments.row.schedule = deserializeJSON( arguments.row.schedule );
        return arguments.row;
    }
    /**
     * Binds optional text explicitly so supported engines preserve SQL nulls.
     * @returns struct
     */
    private struct function textBinding( required string value ) {
        return { "value": arguments.value, "null": !len( arguments.value ), "cfsqltype": "varchar" };
    }
    /**
     * Binds millisecond boundaries as BIGINT instead of the default integer type.
     * @returns struct
     */
    private struct function epochBinding( required numeric value ) {
        return { "value": arguments.value, "cfsqltype": "bigint" };
    }
    /**
     * Returns a Java UUID for a new persisted digest identity.
     * @returns string
     */
    private string function uuid() {
        return variables.uuidGenerator.randomUUID().toString();
    }
    /**
     * Supplies a fresh QueryBuilder through WireBox.
     * @returns QueryBuilder
     */
    private QueryBuilder function newQueryBuilder() provider="QueryBuilder@qb" {
    }

}
