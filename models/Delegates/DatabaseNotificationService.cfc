component singleton {

    property name="wirebox" inject="wirebox";

    /** Keyset pages survive new arrivals and deletion of the boundary row. Existing offset APIs remain compatible. */
    public struct function getNotificationSlice(
        required any notifiable,
        string afterCursor = "",
        numeric maxRows = 25,
        any constraints,
        string archiveMode = "active",
        boolean unread = false,
        string channelName = "database"
    ) {
        var source = cursor( argumentCollection = arguments );
        var provider = source.getChannel();
        var query = source.getQB();
        if ( arguments.unread ) {
            query.whereNull( "readDate" );
        }
        var mutationQuery = source.getMutationQuery().clone();
        if ( len( arguments.afterCursor ) ) {
            var boundary = decodeCursor( arguments.afterCursor, arguments.notifiable );
            query.where( ( nested ) => nested
                .where( "createdDate", "<", provider.bindCursorTimestamp( boundary.timestamp ) )
                .orWhere( ( tied ) => tied
                    .where( "createdDate", provider.bindCursorTimestamp( boundary.timestamp ) )
                    .where( "id", "<", provider.bindCursorIdentifier( boundary.id ) ) ) );
        }
        var rows = query
            .select( provider.getTableName() & ".*" )
            .selectRaw( provider.getCursorTimestampExpression() & " AS cursor_timestamp" )
            .orderByDesc( "createdDate" )
            .orderByDesc( "id" )
            .limit( arguments.maxRows + 1 )
            .get();
        var hasMore = rows.len() > arguments.maxRows;
        if ( hasMore ) {
            arrayDeleteAt( rows, rows.len() );
        }
        var nextCursor = "";
        if ( hasMore ) {
            var last = rows[ rows.len() ];
            nextCursor = encodeCursor( {
                "id": toString( last.id ),
                "timestamp": toString( last.cursor_timestamp ),
                "recipientId": toString( arguments.notifiable.getNotifiableId() ),
                "recipientType": arguments.notifiable.getNotifiableType()
            } );
        }
        return {
            "results": rows.map( ( row ) => variables.wirebox
                .getInstance( "DatabaseNotification@megaphone" )
                .setChannel( provider )
                .setMutationQuery( mutationQuery.clone() )
                .populateFromDatabaseRow( row ) ),
            "nextCursor": nextCursor,
            "hasMore": hasMore
        };
    }

    private string function encodeCursor( required struct boundary ) {
        return replace(
            replace(
                replace(
                    toBase64( serializeJSON( arguments.boundary ), "UTF-8" ),
                    "+",
                    "-",
                    "all"
                ),
                "/",
                "_",
                "all"
            ),
            "=",
            "",
            "all"
        );
    }

    private struct function decodeCursor( required string token, required any notifiable ) {
        try {
            if ( len( arguments.token ) > 1024 || !reFind( "^[A-Za-z0-9_-]+$", arguments.token ) ) {
                throw( message = "Invalid token." );
            }
            var encoded = replace(
                replace( arguments.token, "-", "+", "all" ),
                "_",
                "/",
                "all"
            );
            while ( len( encoded ) mod 4 ) {
                encoded &= "=";
            }
            var boundary = deserializeJSON( charsetEncode( binaryDecode( encoded, "base64" ), "UTF-8" ) );
            if (
                !isStruct( boundary ) || !isSimpleValue( boundary.id ?: [] ) || !len( boundary.id ) || len(
                    boundary.id
                ) > 128 || !isSimpleValue( boundary.timestamp ?: [] ) || !reFind(
                    "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?$",
                    boundary.timestamp
                ) || boundary.recipientId != toString( arguments.notifiable.getNotifiableId() ) || boundary.recipientType != arguments.notifiable.getNotifiableType()
            ) {
                throw( message = "Invalid boundary." );
            }
            createObject( "java", "java.sql.Timestamp" ).valueOf( boundary.timestamp );
            return boundary;
        } catch ( any ignored ) {
            throw(
                type = "Megaphone.Database.InvalidCursor",
                message = "The notification cursor is invalid for this recipient."
            );
        }
    }

    public DatabaseNotificationCursor function getNotifications(
        required any notifiable,
        string channelName = "database",
        numeric initialPage = 1,
        numeric maxRows = 25,
        any constraints,
        string archiveMode = "all"
    ) {
        return cursor( argumentCollection = arguments ).fetch();
    }

    public DatabaseNotificationCursor function getReadNotifications(
        required any notifiable,
        string channelName = "database",
        numeric initialPage = 1,
        numeric maxRows = 25,
        any constraints,
        string archiveMode = "all"
    ) {
        return cursor( argumentCollection = arguments )
            .configureQuery( ( qb ) => qb.whereNotNull( "readDate" ), false )
            .fetch();
    }

    public DatabaseNotificationCursor function getUnreadNotifications(
        required any notifiable,
        string channelName = "database",
        numeric initialPage = 1,
        numeric maxRows = 25,
        any constraints,
        string archiveMode = "all"
    ) {
        return cursor( argumentCollection = arguments )
            .configureQuery( ( qb ) => qb.whereNull( "readDate" ), false )
            .fetch();
    }

    public numeric function countUnreadNotifications(
        required any notifiable,
        string channelName = "database",
        any constraints,
        string archiveMode = "all"
    ) {
        return cursor( argumentCollection = arguments )
            .getQB()
            .whereNull( "readDate" )
            .count();
    }

    /** Missing, foreign, and currently unauthorized entries return null. */
    public any function getNotification(
        required any notifiable,
        required string id,
        string channelName = "database",
        any constraints,
        string archiveMode = "all"
    ) {
        var result = cursor( argumentCollection = arguments );
        result.configureQuery( ( qb ) => qb.where( "id", result.getChannel().bindIdentifier( id ) ) ).fetch();
        if ( result.getResults().isEmpty() ) {
            return;
        }
        return result.getResults()[ 1 ];
    }

    public array function snapshotIds(
        required any notifiable,
        string channelName = "database",
        any constraints,
        string archiveMode = "all"
    ) {
        return cursor( argumentCollection = arguments )
            .getQB()
            .clearSelect()
            .select( "id" )
            .get()
            .map( ( row ) => toString( row.id ) );
    }

    public void function markSnapshotAsRead(
        required any notifiable,
        required array ids,
        string channelName = "database",
        any constraints,
        date readDate = now()
    ) {
        if ( arguments.ids.isEmpty() ) {
            return;
        }
        var result = cursor( argumentCollection = arguments );
        result
            .getQB()
            .whereIn( "id", arguments.ids.map( ( id ) => result.getChannel().bindIdentifier( id ) ) )
            .whereNull( "readDate" )
            .update( { "readDate": arguments.readDate } );
    }

    /** Idempotent storage/import only. Never routes or dispatches other channels. */
    public DatabaseNotification function importNotification(
        required any notifiable,
        required string id,
        required string type,
        required struct data,
        date createdDate = now(),
        any readDate,
        string channelName = "database",
        string groupKey = "",
        any archivedDate
    ) {
        var result = cursor( notifiable = arguments.notifiable, channelName = arguments.channelName );
        var values = {
            "id": result.getChannel().bindIdentifier( arguments.id ),
            "type": arguments.type,
            "notifiableId": arguments.notifiable.getNotifiableId(),
            "notifiableType": arguments.notifiable.getNotifiableType(),
            "data": serializeJSON( arguments.data ),
            "createdDate": arguments.createdDate,
            "readDate": {
                "value": arguments.readDate ?: "",
                "null": isNull( arguments.readDate ),
                "cfsqltype": "timestamp"
            }
        };
        if ( result.getChannel().supportsInboxState() ) {
            values[ "groupKey" ] = arguments.groupKey;
            values[ "archivedDate" ] = {
                "value": arguments.archivedDate ?: "",
                "null": isNull( arguments.archivedDate ),
                "cfsqltype": "timestamp"
            };
        } else if ( len( arguments.groupKey ) || !isNull( arguments.archivedDate ) ) {
            throw(
                type = "Megaphone.Database.InboxStateRequired",
                message = "Install the inbox state migration and enable inboxState on this channel."
            );
        }
        result
            .getQB()
            .clone()
            .clearOrders()
            .insertIgnore( values );
        var stored = getNotification( arguments.notifiable, arguments.id, arguments.channelName );
        if ( isNull( stored ) || stored.getType() != arguments.type ) {
            throw(
                type = "Megaphone.Database.ImportConflict",
                message = "An import ID is already owned by another recipient or notification type."
            );
        }
        return stored;
    }

    /** Includes archived entries; prunes bounded batches of recipient-owned inbox rows. */
    public numeric function pruneNotifications(
        required any notifiable,
        numeric keep = 1000,
        numeric batchSize = 200,
        string channelName = "database"
    ) {
        if (
            arguments.keep < 0 || arguments.batchSize < 1 || fix( arguments.keep ) != arguments.keep || fix(
                arguments.batchSize
            ) != arguments.batchSize
        ) {
            throw(
                type = "Megaphone.Database.InvalidRetention",
                message = "Retention and batch size must be valid integers."
            );
        }
        var result = cursor( argumentCollection = arguments );
        var source = result.getQB();
        var ids = source
            .clone()
            .clearSelect()
            .select( "id" )
            .orderByDesc( "createdDate" )
            .orderByDesc( "id" )
            .offset( arguments.keep )
            .limit( arguments.batchSize )
            .get()
            .map( ( row ) => row.id );
        if ( ids.isEmpty() ) {
            return 0;
        }
        source.whereIn( "id", ids.map( ( id ) => result.getChannel().bindIdentifier( id ) ) ).delete();
        return ids.len();
    }

    private DatabaseNotificationCursor function cursor(
        required any notifiable,
        string channelName = "database",
        numeric initialPage = 1,
        numeric maxRows = 25,
        any constraints,
        string archiveMode = "all"
    ) {
        if (
            arguments.initialPage < 1 || fix( arguments.initialPage ) != arguments.initialPage || arguments.maxRows < 1 || fix(
                arguments.maxRows
            ) != arguments.maxRows
        ) {
            throw(
                type = "Megaphone.Database.InvalidPagination",
                message = "Page and page size must be positive integers."
            );
        }
        if ( !listFind( "all,active,archived", arguments.archiveMode ) ) {
            throw(
                type = "Megaphone.Database.InvalidArchiveMode",
                message = "Archive mode must be all, active, or archived."
            );
        }
        var channel = variables.wirebox.getInstance( "megaphone:#arguments.channelName#" );
        if ( channel.getProviderName() != "DatabaseProvider" ) {
            throw(
                type = "Megaphone.Configuration.InvalidChannelProvider",
                message = "The requested channel must use DatabaseProvider."
            );
        }
        var qb = variables.wirebox
            .getInstance( "QueryBuilder@qb" )
            .from( channel.getTableName() )
            .mergeDefaultOptions( channel.getQueryOptions() )
            .where( "notifiableId", arguments.notifiable.getNotifiableId() )
            .where( "notifiableType", arguments.notifiable.getNotifiableType() );
        if ( !isNull( arguments.constraints ) ) {
            qb.where( arguments.constraints );
        }
        var mutationQuery = qb.clone();
        if ( arguments.archiveMode != "all" ) {
            if ( !channel.supportsInboxState() ) {
                throw(
                    type = "Megaphone.Database.InboxStateRequired",
                    message = "Archive queries require inboxState on the database channel."
                );
            }
            if ( arguments.archiveMode == "active" ) {
                qb.whereNull( "archivedDate" );
            } else {
                qb.whereNotNull( "archivedDate" );
            }
        }
        return variables.wirebox
            .getInstance( "DatabaseNotificationCursor@megaphone" )
            .setChannel( channel )
            .setQB( qb )
            .setMutationQuery( mutationQuery )
            .setPage( arguments.initialPage )
            .setMaxRows( arguments.maxRows );
    }

}
