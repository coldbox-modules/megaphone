component extends="BaseProvider" accessors="true" {

    public string function getProviderName() {
        return "DatabaseProvider";
    }

    public BaseNotification function notify( required any notifiable, required BaseNotification notification ) {
        newQueryBuilder()
            .table( getTableName() )
            .mergeDefaultOptions( getQueryOptions() )
            .insert( {
                "id": bindIdentifier( notification.getId() ),
                "type": notification.getNotificationType(),
                "notifiableId": arguments.notifiable.getNotifiableId(),
                "notifiableType": arguments.notifiable.getNotifiableType(),
                "data": serializeJSON( notification.routeForType( "database", notifiable, getName() ) )
            } );

        return arguments.notification;
    }

    public string function getTableName() {
        var properties = getProperties();
        return structKeyExists( properties, "table" ) ? properties.table : "megaphone_notifications";
    }

    /** PostgreSQL UUID columns require OTHER unless the JDBC driver uses unspecified strings. */
    public struct function bindIdentifier( required string id ) {
        var properties = getProperties();
        return {
            "value": arguments.id,
            "cfsqltype": structKeyExists( properties, "idSqlType" ) ? properties.idSqlType : "varchar"
        };
    }

    /** Configured by the consumer's database adapter; preserve its full timestamp precision. */
    public string function getCursorTimestampExpression() {
        var properties = getProperties();
        var expression = structKeyExists( properties, "cursorTimestampExpression" ) ? properties.cursorTimestampExpression : "";
        if ( !len( expression ) ) {
            throw(
                type = "Megaphone.Database.CursorAdapterRequired",
                message = "Cursor pagination requires a database timestamp text expression."
            );
        }
        return expression;
    }

    public struct function bindCursorTimestamp( required string timestamp ) {
        var properties = getProperties();
        return {
            "value": arguments.timestamp,
            "cfsqltype": structKeyExists( properties, "cursorTimestampSqlType" ) ? properties.cursorTimestampSqlType : "timestamp"
        };
    }

    public struct function bindCursorIdentifier( required string id ) {
        var properties = getProperties();
        var pattern = structKeyExists( properties, "cursorIdentifierPattern" ) ? properties.cursorIdentifierPattern : "";
        if ( len( pattern ) && !reFindNoCase( pattern, arguments.id ) ) {
            throw(
                type = "Megaphone.Database.InvalidCursor",
                message = "The notification cursor identifier is invalid."
            );
        }
        return bindIdentifier( arguments.id );
    }

    /** Opt in only after applying the additional inbox state migration. */
    public boolean function supportsInboxState() {
        var properties = getProperties();
        return structKeyExists( properties, "inboxState" ) && properties.inboxState;
    }

    public struct function getQueryOptions() {
        var options = {};
        var properties = getProperties();
        if ( structKeyExists( properties, "queryOptions" ) ) {
            options.append( properties.queryOptions );
        }
        if ( getProperties().keyExists( "datasource" ) ) {
            options.append( { "datasource": getProperties().datasource } );
        }
        return options;
    }

    private QueryBuilder function newQueryBuilder() provider="QueryBuilder@qb" {
    }

}
