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
        newEventQuery().insertIgnore( values );
        var rows = newEventQuery()
            .where( "namespace", identity.namespace )
            .where( "eventKey", identity.eventKey )
            .where( "version", identity.version )
            .get();
        var stored = rows[ 1 ];
        if ( stored.type != arguments.type || stored.payloadHash != arguments.payloadHash ) {
            throw(
                type = "Megaphone.Events.IdentityConflict",
                message = "An event identity already refers to different content."
            );
        }
        stored.payload = deserializeJSON( stored.payload );
        stored[ "created" ] = stored.id == values.id;
        return stored;
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
