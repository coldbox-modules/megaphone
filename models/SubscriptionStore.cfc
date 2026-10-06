/** Stable browser-registration identities. Store only encrypted subscription material supplied by a cipher adapter. */
component accessors="true" {

    property name="properties";
    function init( struct properties = {} ) {
        variables.properties = arguments.properties;
        return this;
    }

    public struct function register(
        required any notifiable,
        required string endpointHash,
        required string sealedData,
        string label = "",
        string existingId = "",
        any expiresDate
    ) {
        var owner = recipient( arguments.notifiable );
        if (
            !reFindNoCase( "^[a-f0-9]{64}$", arguments.endpointHash ) || !len( arguments.sealedData ) || len(
                arguments.label
            ) > 100
        ) {
            throw(
                type = "Megaphone.Push.InvalidRegistration",
                message = "An endpoint hash, sealed subscription, and valid label are required."
            );
        }
        var endpointHash = lCase( arguments.endpointHash );
        var candidateId = uuid();
        transaction {
            try {
                newSubscriptionQuery().insertIgnore( {
                    "id": candidateId,
                    "recipientType": owner.recipientType,
                    "recipientId": owner.recipientId,
                    "endpointHash": endpointHash,
                    "endpointKey": endpointHash,
                    "sealedData": arguments.sealedData,
                    "label": arguments.label,
                    "active": booleanBinding( true ),
                    "createdDate": now(),
                    "renewedDate": now(),
                    "expiresDate": timestamp( arguments.expiresDate ?: javacast( "null", "" ) )
                } );
                var existingId = arguments.existingId;
                var rows = newSubscriptionQuery()
                    .where( ( query ) => query.where( "endpointKey", endpointHash ).orWhere( "id", existingId ) )
                    .orderBy( "id" )
                    .lockForUpdate()
                    .get();
                var endpointRows = rows.filter( ( row ) => ( row.endpointKey ?: "" ) == endpointHash );
                if ( endpointRows.isEmpty() ) {
                    throw(
                        type = "Megaphone.Push.ConcurrentRegistration",
                        message = "Registration changed concurrently; retry enrollment."
                    );
                }
                var endpoint = endpointRows[ 1 ];
                var selected = endpoint;
                if ( len( existingId ) ) {
                    var selectedRows = rows.filter( ( row ) => row.id == existingId && row.recipientType == owner.recipientType && row.recipientId == owner.recipientId );
                    if ( selectedRows.isEmpty() ) {
                        throw(
                            type = "Megaphone.Push.UnknownRegistration",
                            message = "The requested browser registration is not owned by this recipient."
                        );
                    }
                    selected = selectedRows[ 1 ];
                } else if ( endpoint.recipientType != owner.recipientType || endpoint.recipientId != owner.recipientId ) {
                    // A shared browser moves to a new owned ID; the previous account's exclusions stay separate.
                    retire( endpoint.id );
                    newSubscriptionQuery().insert( {
                        "id": candidateId,
                        "recipientType": owner.recipientType,
                        "recipientId": owner.recipientId,
                        "endpointHash": endpointHash,
                        "endpointKey": endpointHash,
                        "sealedData": arguments.sealedData,
                        "label": arguments.label,
                        "active": booleanBinding( true ),
                        "createdDate": now(),
                        "renewedDate": now(),
                        "expiresDate": timestamp( arguments.expiresDate ?: javacast( "null", "" ) )
                    } );
                    selected = { "id": candidateId, "label": arguments.label };
                }
                if ( endpoint.id != selected.id ) {
                    retire( endpoint.id );
                }
                var label = len( trim( arguments.label ) ) ? arguments.label : selected.label;
                if ( !len( trim( label ) ) ) {
                    throw(
                        type = "Megaphone.Push.InvalidRegistration",
                        message = "A recognizable registration label is required."
                    );
                }
                newSubscriptionQuery()
                    .where( "id", selected.id )
                    .update( {
                        "endpointHash": endpointHash,
                        "endpointKey": endpointHash,
                        "sealedData": arguments.sealedData,
                        "label": label,
                        "active": booleanBinding( true ),
                        "renewedDate": now(),
                        "retiredDate": timestamp(),
                        "expiresDate": timestamp( arguments.expiresDate ?: javacast( "null", "" ) )
                    } );
                return ownedQuery( owner )
                    .where( "id", selected.id )
                    .select( publicColumns() )
                    .get()[ 1 ];
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
    }

    public array function registrations( required any notifiable, boolean activeOnly = true, date clock = now() ) {
        var query = ownedQuery( recipient( arguments.notifiable ) );
        if ( arguments.activeOnly ) {
            var clock = arguments.clock;
            query
                .where( "active", booleanBinding( true ) )
                .where( ( query ) => query.whereNull( "expiresDate" ).orWhere( "expiresDate", ">", clock ) );
        }
        return query
            .select( publicColumns() )
            .orderBy( "createdDate" )
            .orderBy( "id" )
            .get();
    }

    /** Only delivery infrastructure should request encrypted credential material. */
    public any function activeRegistration( required any notifiable, required string id, date clock = now() ) {
        var clock = arguments.clock;
        var rows = ownedQuery( recipient( arguments.notifiable ) )
            .where( "id", arguments.id )
            .where( "active", booleanBinding( true ) )
            .where( ( query ) => query.whereNull( "expiresDate" ).orWhere( "expiresDate", ">", clock ) )
            .get();
        if ( rows.isEmpty() ) {
            return;
        }
        return rows[ 1 ];
    }

    public boolean function rename( required any notifiable, required string id, required string label ) {
        if ( !len( trim( arguments.label ) ) || len( arguments.label ) > 100 ) {
            throw( type = "Megaphone.Push.InvalidRegistration", message = "A valid registration label is required." );
        }
        transaction {
            var query = ownedQuery( recipient( arguments.notifiable ) ).where( "id", arguments.id );
            if (
                query
                    .clone()
                    .lockForUpdate()
                    .get()
                    .isEmpty()
            ) {
                return false;
            }
            query.update( { "label": arguments.label } );
            return true;
        }
    }

    public boolean function disconnect( required any notifiable, required string id ) {
        transaction {
            var rows = ownedQuery( recipient( arguments.notifiable ) )
                .where( "id", arguments.id )
                .lockForUpdate()
                .get();
            if ( rows.isEmpty() ) {
                return false;
            }
            if ( !rows[ 1 ].active ) {
                return true;
            }
            retire( arguments.id );
            return true;
        }
    }

    public void function setExcluded(
        required any notifiable,
        required string notificationType,
        required string deviceId,
        required boolean excluded
    ) {
        var owner = recipient( arguments.notifiable );
        if ( !len( trim( arguments.notificationType ) ) || len( arguments.notificationType ) > 160 ) {
            throw( type = "Megaphone.Push.InvalidExclusion", message = "A valid notification type is required." );
        }
        transaction {
            if (
                ownedQuery( owner )
                    .where( "id", arguments.deviceId )
                    .lockForUpdate()
                    .get()
                    .isEmpty()
            ) {
                throw(
                    type = "Megaphone.Push.UnknownRegistration",
                    message = "This recipient does not own the selected registration."
                );
            }
            var values = {
                "recipientType": owner.recipientType,
                "recipientId": owner.recipientId,
                "notificationType": arguments.notificationType,
                "deviceId": arguments.deviceId
            };
            if ( arguments.excluded ) {
                newExclusionQuery().insertIgnore( values );
            } else {
                newExclusionQuery()
                    .where( "recipientType", owner.recipientType )
                    .where( "recipientId", owner.recipientId )
                    .where( "notificationType", arguments.notificationType )
                    .where( "deviceId", arguments.deviceId )
                    .delete();
            }
        }
    }

    public array function excludedIds( required any notifiable, required string notificationType ) {
        var owner = recipient( arguments.notifiable );
        return newExclusionQuery()
            .where( "recipientType", owner.recipientType )
            .where( "recipientId", owner.recipientId )
            .where( "notificationType", arguments.notificationType )
            .orderBy( "deviceId" )
            .get()
            .map( ( row ) => row.deviceId );
    }

    public numeric function pruneInactive( required date beforeDate, numeric limit = 100 ) {
        if ( arguments.limit < 1 || fix( arguments.limit ) != arguments.limit ) {
            throw( type = "Megaphone.Push.InvalidBatch", message = "Batch size must be a positive integer." );
        }
        var rows = newSubscriptionQuery()
            .where( "active", booleanBinding( false ) )
            .where( "retiredDate", "<", arguments.beforeDate )
            .orderBy( "retiredDate" )
            .orderBy( "id" )
            .limit( arguments.limit )
            .get();
        var removed = 0;
        for ( var row in rows ) {
            transaction {
                var locked = newSubscriptionQuery()
                    .where( "id", row.id )
                    .where( "active", booleanBinding( false ) )
                    .where( "retiredDate", "<", arguments.beforeDate )
                    .lockForUpdate()
                    .get();
                if ( locked.isEmpty() ) {
                    continue;
                }
                newExclusionQuery().where( "deviceId", row.id ).delete();
                newSubscriptionQuery().where( "id", row.id ).delete();
                removed++;
            }
        }
        return removed;
    }

    public void function deleteRecipient( required any notifiable ) {
        var owner = recipient( arguments.notifiable );
        transaction {
            newExclusionQuery()
                .where( "recipientType", owner.recipientType )
                .where( "recipientId", owner.recipientId )
                .delete();
            ownedQuery( owner ).delete();
        }
    }

    private void function retire( required string id ) {
        newSubscriptionQuery()
            .where( "id", arguments.id )
            .update( {
                "active": booleanBinding( false ),
                "endpointKey": { "value": "", "null": true, "cfsqltype": "varchar" },
                "sealedData": { "value": "", "null": false, "cfsqltype": "varchar" },
                "retiredDate": timestamp( now() )
            } );
    }
    private array function publicColumns() {
        return [
            "id",
            "label",
            "active",
            "createdDate",
            "renewedDate",
            "expiresDate",
            "retiredDate"
        ];
    }
    private struct function recipient( required any notifiable ) {
        var owner = {
            "recipientType": arguments.notifiable.getNotifiableType(),
            "recipientId": arguments.notifiable.getNotifiableId()
        };
        if (
            !len( trim( owner.recipientType ) ) || len( owner.recipientType ) > 80 || !len( trim( owner.recipientId ) ) || len(
                owner.recipientId
            ) > 100
        ) {
            throw( type = "Megaphone.Push.InvalidRecipient", message = "A valid recipient identity is required." );
        }
        return owner;
    }
    private any function ownedQuery( required struct owner ) {
        return newSubscriptionQuery()
            .where( "recipientType", arguments.owner.recipientType )
            .where( "recipientId", arguments.owner.recipientId );
    }
    private struct function booleanBinding( required boolean value ) {
        return { "value": arguments.value, "cfsqltype": "bit" };
    }
    private struct function timestamp( any value ) {
        return { "value": arguments.value ?: "", "null": isNull( arguments.value ), "cfsqltype": "timestamp" };
    }
    private string function uuid() {
        return createObject( "java", "java.util.UUID" ).randomUUID().toString();
    }
    private any function newSubscriptionQuery() {
        return newQueryBuilder()
            .from( variables.properties.table ?: "megaphone_subscriptions" )
            .mergeDefaultOptions( variables.properties.queryOptions ?: {} );
    }
    private any function newExclusionQuery() {
        return newQueryBuilder()
            .from( variables.properties.exclusionsTable ?: "megaphone_device_exclusions" )
            .mergeDefaultOptions( variables.properties.queryOptions ?: {} );
    }
    private any function newQueryBuilder() provider="QueryBuilder@qb" {
    }

}
