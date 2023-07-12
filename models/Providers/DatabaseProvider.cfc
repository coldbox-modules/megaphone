component extends="BaseProvider" accessors="true" {

    public string function getProviderName() {
        return "DatabaseProvider";
    }

    public BaseNotification function notify( required any notifiable, required BaseNotification notification ) {
        newQueryBuilder()
            .table( getTableName() )
            .mergeDefaultOptions( getQueryOptions() )
            .insert( {
                "id": notification.getId(),
                "type": notification.getNotificationType(),
                "notifiableId": arguments.notifiable.getNotifiableId(),
                "notifiableType": arguments.notifiable.getNotifiableType(),
                "data": serializeJSON( notification.routeForType( "database", notifiable, getName() ) )
            } );

        return arguments.notification;
    }

    public string function getTableName() {
        return getProperties()?.table ?: "megaphone_notifications";
    }

    public struct function getQueryOptions() {
        var options = {};
        options.append( getProperties()?.queryOptions ?: {} );
        if ( getProperties().keyExists( "datasource" ) ) {
            options.append( { "datasource": getProperties().datasource } );
        }
        return options;
    }

    private QueryBuilder function newQueryBuilder() provider="QueryBuilder@qb" {
    }

}
