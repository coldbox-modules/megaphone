/** Durable event identity, separate from presentation history. Uses the caller's transaction. */
component accessors="true" {

    property name="properties" type="struct" setter="false";
    property name="uuidGenerator" inject="java:java.util.UUID";

    /**
     * Stores the event persistence configuration.
     * @returns EventStore
     */
    public EventStore function init( struct properties = {} ) {
        variables.properties = arguments.properties;
        return this;
    }

    /**
     * Persists a stable event identity without replacing an existing replay.
     * @returns struct
     */
    public struct function record(
        required string namespace,
        required string eventKey,
        required numeric version,
        required string type,
        required struct payload,
        required string payloadHash,
        date createdDate = now(),
        string notificationMapping = ""
    ) {
        return recordMany( [ arguments ] )[ 1 ];
    }

    /** Records a batch in one caller transaction; identical replays never replace snapshots. */
    public array function recordMany( required array events ) {
        var prepared = arguments.events.map( ( event ) => prepareEvent( argumentCollection = event ) );
        var result = [];
        if ( prepared.isEmpty() ) {
            return result;
        }
        var bulk = new megaphone.models.Storage.BulkRecords();
        var size = bulk.insertSize( prepared[ 1 ].values );
        transaction {
            try {
                for ( var offset = 1; offset <= prepared.len(); offset += size ) {
                    var batch = prepared.slice( offset, min( size, prepared.len() - offset + 1 ) );
                    newEventQuery().insertIgnore( batch.map( ( entry ) => entry.values ) );
                    var records = bulk.read(
                        () => newEventQuery(),
                        batch.map( ( entry ) => entry.identity ),
                        getTableName()
                    );
                    for ( var index = 1; index <= batch.len(); index++ ) {
                        var stored = records[ index ][ 1 ];
                        if (
                            stored.type != batch[ index ].values.type || stored.payloadHash != batch[ index ].values.payloadHash
                        ) {
                            throw(
                                type = "Megaphone.Events.IdentityConflict",
                                message = "An event identity already refers to different content."
                            );
                        }
                        stored.payload = deserializeJSON( stored.payload );
                        stored.created = stored.id == batch[ index ].values.id;
                        result.append( stored );
                    }
                }
            } catch ( any error ) {
                transactionRollback();
                rethrow;
            }
        }
        return result;
    }

    private struct function prepareEvent(
        required string namespace,
        required string eventKey,
        required numeric version,
        required string type,
        required struct payload,
        required string payloadHash,
        date createdDate = now(),
        string notificationMapping = ""
    ) {
        if (
            !len( trim( arguments.namespace ) ) || !len( trim( arguments.eventKey ) ) ||
            !len( trim( arguments.type ) ) || !len( trim( arguments.payloadHash ) ) ||
            arguments.version < 1 || fix( arguments.version ) != arguments.version
        ) {
            throw(
                type = "Megaphone.Events.InvalidIdentity",
                message = "Event identity, type, hash, and a positive integer version are required."
            );
        }
        var identity = {
            "namespace": arguments.namespace,
            "eventKey": arguments.eventKey,
            "version": arguments.version
        };
        var values = duplicate( identity );
        values.append( {
            "id": variables.uuidGenerator.randomUUID().toString(),
            "type": arguments.type,
            "payloadHash": arguments.payloadHash,
            "payload": serializeJSON( arguments.payload ),
            "createdDate": arguments.createdDate,
            "notificationMapping": {
                "value": arguments.notificationMapping,
                "null": !len( arguments.notificationMapping ),
                "cfsqltype": "varchar"
            }
        } );
        identity[ "namespace" ] = {
            "value": arguments.namespace,
            "cfsqltype": "varchar",
            "null": false,
            "list": false
        };
        identity[ "eventKey" ] = {
            "value": arguments.eventKey,
            "cfsqltype": "varchar",
            "null": false,
            "list": false
        };
        identity[ "version" ] = {
            "value": arguments.version,
            "cfsqltype": "integer",
            "null": false,
            "list": false
        };
        return { "identity": identity, "values": values };
    }

    /**
     * Loads a stored record by ID, optionally locking it in the caller's transaction.
     * @returns any
     */
    public any function find( required string id ) {
        var rows = newEventQuery().where( "id", arguments.id ).get();
        if ( rows.isEmpty() ) {
            return;
        }
        var stored = rows[ 1 ];
        stored.payload = deserializeJSON( stored.payload );
        return stored;
    }

    /**
     * Builds a query for the configured event table.
     * @returns any
     */
    private any function newEventQuery() {
        return newQueryBuilder().from( getTableName() ).mergeDefaultOptions( getQueryOptions() );
    }

    /**
     * Returns the configured table name, or this store's default.
     * @returns string
     */
    public string function getTableName() {
        return variables.properties.table ?: "megaphone_events";
    }
    /**
     * Returns query options with an explicitly configured datasource taking precedence.
     * @returns struct
     */
    public struct function getQueryOptions() {
        var options = duplicate( variables.properties.queryOptions ?: {} );
        if ( variables.properties.keyExists( "datasource" ) ) {
            options.datasource = variables.properties.datasource;
        }
        return options;
    }

    /**
     * Supplies a fresh QueryBuilder through WireBox.
     * @returns QueryBuilder
     */
    private QueryBuilder function newQueryBuilder() provider="QueryBuilder@qb" {
    }

}
