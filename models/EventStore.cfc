/** Durable event identity, separate from presentation history. Uses the caller's transaction. */
component accessors="true" {

    property name="properties" type="struct" setter="false";
    property name="uuidGenerator" inject="java:java.util.UUID";

    public EventStore function init( struct properties = {} ) {
        variables.properties = arguments.properties;
        return this;
    }

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

    public any function find( required string id ) {
        var rows = newEventQuery().where( "id", arguments.id ).get();
        if ( rows.isEmpty() ) {
            return;
        }
        var stored = rows[ 1 ];
        stored.payload = deserializeJSON( stored.payload );
        return stored;
    }

    private any function newEventQuery() {
        return newQueryBuilder().from( getTableName() ).mergeDefaultOptions( getQueryOptions() );
    }

    public string function getTableName() {
        return variables.properties.table ?: "megaphone_events";
    }
    public struct function getQueryOptions() {
        var options = duplicate( variables.properties.queryOptions ?: {} );
        if ( variables.properties.keyExists( "datasource" ) ) {
            options.datasource = variables.properties.datasource;
        }
        return options;
    }

    private QueryBuilder function newQueryBuilder() provider="QueryBuilder@qb" {
    }

}
