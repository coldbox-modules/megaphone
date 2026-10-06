component accessors="true" {

    property name="channel";
    property name="mutationQuery";

    property name="id";
    property name="type" type="string";
    property name="notifiableType" type="string";
    property name="notifiableId" type="any";
    property name="data" type="struct";
    property name="readDate" type="date";
    property name="createdDate" type="date";
    property name="archivedDate";
    property name="groupKey" default="";

    public DatabaseNotification function populateFromDatabaseRow( required struct properties ) {
        variables.id = toString( arguments.properties.id );
        variables.type = arguments.properties.type;
        variables.notifiableType = arguments.properties.notifiableType;
        variables.notifiableId = arguments.properties.notifiableId;
        variables.data = deserializeJSON( arguments.properties.data );
        variables.readDate = arguments.properties.readDate;
        variables.createdDate = arguments.properties.createdDate;
        variables.archivedDate = arguments.properties.archivedDate ?: javacast( "null", "" );
        variables.groupKey = arguments.properties.groupKey ?: "";

        return this;
    }

    public struct function getMemento() {
        var memento = {
            "id": getId(),
            "type": getType(),
            "notifiableType": getNotifiableType(),
            "notifiableId": getNotifiableId(),
            "data": getData(),
            "readDate": getReadDate(),
            "createdDate": getCreatedDate()
        };
        if ( variables.channel.supportsInboxState() ) {
            memento.groupKey = variables.groupKey;
            memento.archivedDate = variables.archivedDate;
        }
        return memento;
    }

    public DatabaseNotification function markAsRead( date readDate = now() ) {
        ownedQuery().whereNull( "readDate" ).update( { "readDate": arguments.readDate } );
        refreshOwnedState();
        return this;
    }

    public void function delete() {
        ownedQuery().delete();
    }

    private QueryBuilder function newQueryBuilder() provider="QueryBuilder@qb" {
    }

    public DatabaseNotification function archive( date archivedDate = now() ) {
        requireInboxState();
        ownedQuery().whereNull( "archivedDate" ).update( { "archivedDate": arguments.archivedDate } );
        refreshOwnedState();
        return this;
    }

    public DatabaseNotification function unarchive() {
        requireInboxState();
        ownedQuery().update( { "archivedDate": { "value": "", "null": true, "cfsqltype": "timestamp" } } );
        refreshOwnedState();
        return this;
    }

    private void function refreshOwnedState() {
        var rows = ownedQuery().get();
        if ( !rows.isEmpty() ) {
            populateFromDatabaseRow( rows[ 1 ] );
        }
    }

    private void function requireInboxState() {
        if ( !variables.channel.supportsInboxState() ) {
            throw(
                type = "Megaphone.Database.InboxStateRequired",
                message = "Archiving requires inboxState on the database channel."
            );
        }
    }

    private any function ownedQuery() {
        var qb = !isNull( variables.mutationQuery ) ? variables.mutationQuery.clone() : newQueryBuilder()
            .mergeDefaultOptions( variables.channel.getQueryOptions() )
            .from( variables.channel.getTableName() );
        return qb
            .where( "id", variables.channel.bindIdentifier( variables.id ) )
            .where( "notifiableId", variables.notifiableId )
            .where( "notifiableType", variables.notifiableType );
    }

}
