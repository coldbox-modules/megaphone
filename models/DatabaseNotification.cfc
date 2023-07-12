component accessors="true" {

    property name="channel";

    property name="id";
    property name="type" type="string";
    property name="notifiableType" type="string";
    property name="notifiableId" type="any";
    property name="data" type="struct";
    property name="readDate" type="date";
    property name="createdDate" type="date";

    public DatabaseNotification function populateFromDatabaseRow( required struct properties ) {
        variables.id = arguments.properties.id;
        variables.type = arguments.properties.type;
        variables.notifiableType = arguments.properties.notifiableType;
        variables.notifiableId = arguments.properties.notifiableId;
        variables.data = deserializeJSON( arguments.properties.data );
        variables.readDate = arguments.properties.readDate;
        variables.createdDate = arguments.properties.createdDate;

        return this;
    }

    public struct function getMemento() {
        return {
            "id": getId(),
            "type": getType(),
            "notifiableType": getNotifiableType(),
            "notifiableId": getNotifiableId(),
            "data": getData(),
            "readDate": getReadDate(),
            "createdDate": getCreatedDate()
        };
    }

    public DatabaseNotification function markAsRead( date readDate = now() ) {
        newQueryBuilder()
            .mergeDefaultOptions( variables.channel.getQueryOptions() )
            .from( variables.channel.getTableName() )
            .where( "id", variables.id )
            .update( { "readDate": arguments.readDate } );
        variables.readDate = arguments.readDate;
        return this;
    }

    public void function delete() {
        newQueryBuilder()
            .mergeDefaultOptions( variables.channel.getQueryOptions() )
            .from( variables.channel.getTableName() )
            .where( "id", variables.id )
            .delete();
    }

    private QueryBuilder function newQueryBuilder() provider="QueryBuilder@qb" {
    }

}
