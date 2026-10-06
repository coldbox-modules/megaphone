/** Durable event identity, separate from presentation history. Uses the caller's transaction. */
component accessors="true" {

    property name="properties";

    function init( struct properties = {} ) {
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
        date createdDate = now()
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
            "id": createObject( "java", "java.util.UUID" ).randomUUID().toString(),
            "type": arguments.type,
            "payloadHash": arguments.payloadHash,
            "payload": serializeJSON( arguments.payload ),
            "createdDate": arguments.createdDate
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
        return newQueryBuilder()
            .from( variables.properties.table ?: "megaphone_events" )
            .mergeDefaultOptions( variables.properties.queryOptions ?: {} );
    }

    private any function newQueryBuilder() provider="QueryBuilder@qb" {
    }

}
