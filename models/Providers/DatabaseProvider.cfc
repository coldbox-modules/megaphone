component extends="BaseProvider" accessors="true" {

    property name="wirebox" inject="wirebox";

    /**
     * Prepares one durable delivery without sending it.
     * @returns DeliveryPreparation
     */
    public DeliveryPreparation function prepareDelivery(
        required any notifiable,
        required any notification,
        required any delivery
    ) {
        var event = variables.wirebox
            .getInstance( "NotificationDeliveryService@megaphone" )
            .getEvent( arguments.delivery.getEventId() );
        var context = arguments.notification.getDeliveryContext( arguments.notifiable, getName() );
        return newDeliveryPreparation().configure( {
            "data": {
                "notifiable": arguments.notifiable,
                "notificationType": arguments.notification.getNotificationType(),
                "createdDate": event.getCreatedDate(),
                "groupKey": context.groupKey ?: "",
                "data": arguments.notification.routeForType(
                    "database",
                    arguments.notifiable,
                    getName(),
                    { "delivery": arguments.delivery }
                )
            }
        } );
    }

    /**
     * Sends one prepared delivery and returns an explicit transport outcome.
     * @returns DeliveryResult
     */
    public DeliveryResult function sendDelivery( required any prepared, required any delivery ) {
        var data = arguments.prepared.getData();
        var entry = variables.wirebox
            .getInstance( "DatabaseNotificationService@megaphone" )
            .importNotification(
                notifiable = data.notifiable,
                id = arguments.delivery.getId(),
                type = data.notificationType,
                data = data.data,
                createdDate = data.createdDate,
                groupKey = data.groupKey,
                channelName = getName()
            );
        return newDeliveryResult().configure( { "status": "accepted", "providerReference": entry.getId() } );
    }

    /**
     * Returns the Provider type used to validate channel configuration.
     * @returns string
     */
    public string function getProviderName() {
        return "DatabaseProvider";
    }

    /**
     * Sends a populated Notification synchronously through its enabled channels.
     * @returns BaseNotification
     */
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

    /**
     * Returns the configured table name, or this store's default.
     * @returns string
     */
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

    /**
     * Binds the captured timestamp text using the channel's database adapter.
     * @returns struct
     */
    public struct function bindCursorTimestamp( required string timestamp ) {
        var properties = getProperties();
        return {
            "value": arguments.timestamp,
            "cfsqltype": structKeyExists( properties, "cursorTimestampSqlType" ) ? properties.cursorTimestampSqlType : "timestamp"
        };
    }

    /**
     * Validates and binds the ID used to break cursor timestamp ties.
     * @returns struct
     */
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

    /**
     * Returns query options with an explicitly configured datasource taking precedence.
     * @returns struct
     */
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

    /**
     * Supplies a fresh QueryBuilder through WireBox.
     * @returns QueryBuilder
     */
    private QueryBuilder function newQueryBuilder() provider="QueryBuilder@qb" {
    }

    /**
     * Supplies a fresh DeliveryPreparation using the application's WireBox mapping.
     * @returns DeliveryPreparation
     */
    private DeliveryPreparation function newDeliveryPreparation() provider="DeliveryPreparation@megaphone" {
    }

    /**
     * Supplies a fresh DeliveryResult using the application's WireBox mapping.
     * @returns DeliveryResult
     */
    private DeliveryResult function newDeliveryResult() provider="DeliveryResult@megaphone" {
    }

}
