component singleton {

    property name="wirebox" inject="wirebox";

    /**
     * Returns all database notifications for a Notifiable.
     * @returns DatabaseNotificationCursor
     */
    public DatabaseNotificationCursor function getNotifications(
        required any notifiable,
        string channelName = "database",
        numeric initialPage = 1,
        numeric maxRows = 25
    ) {
        var channel = variables.wirebox.getInstance( "megaphone:#arguments.channelName#" );

        if ( channel.getProviderName() != "DatabaseProvider" ) {
            throw(
                type = "Megaphone.Configuration.InvalidChannelProvider",
                message = "Channel [#channel.getName()#] is not configured to use the `DatabaseProvider`.  Change the provider in your `megaphone` config struct."
            );
        }

        return variables.wirebox
            .getInstance( "DatabaseNotificationCursor@megaphone" )
            .setChannel( channel )
            .setQB( variables.wirebox.getInstance( "QueryBuilder@qb" ) )
            .setPage( arguments.initialPage )
            .setMaxRows( arguments.maxRows )
            .configureQuery( ( qb ) => {
                qb.from( channel.getTableName() )
                    .mergeDefaultOptions( channel.getQueryOptions() )
                    .where( "notifiableId", notifiable.getNotifiableId() )
                    .where( "notifiableType", notifiable.getNotifiableType() );
            } )
            .fetch();
    }

    /**
     * Returns all read database notifications for a Notifiable.
     * @returns DatabaseNotificationCursor
     */
    public DatabaseNotificationCursor function getReadNotifications(
        required any notifiable,
        string channelName = "database",
        numeric initialPage = 1,
        numeric maxRows = 25
    ) {
        var channel = variables.wirebox.getInstance( "megaphone:#arguments.channelName#" );

        if ( channel.getProviderName() != "DatabaseProvider" ) {
            throw(
                type = "Megaphone.Configuration.InvalidChannelProvider",
                message = "Channel [#channel.getName()#] is not configured to use the `DatabaseProvider`.  Change the provider in your `megaphone` config struct."
            );
        }

        return variables.wirebox
            .getInstance( "DatabaseNotificationCursor@megaphone" )
            .setChannel( channel )
            .setQB( variables.wirebox.getInstance( "QueryBuilder@qb" ) )
            .setPage( arguments.initialPage )
            .setMaxRows( arguments.maxRows )
            .configureQuery( ( qb ) => {
                qb.from( channel.getTableName() )
                    .mergeDefaultOptions( channel.getQueryOptions() )
                    .whereNotNull( "readDate" )
                    .where( "notifiableId", notifiable.getNotifiableId() )
                    .where( "notifiableType", notifiable.getNotifiableType() );
            } )
            .fetch();
    }

    /**
     * Returns all unread database notifications for a Notifiable.
     * @returns DatabaseNotificationCursor
     */
    public DatabaseNotificationCursor function getUnreadNotifications(
        required any notifiable,
        string channelName = "database",
        numeric initialPage = 1,
        numeric maxRows = 25
    ) {
        var channel = variables.wirebox.getInstance( "megaphone:#arguments.channelName#" );

        if ( channel.getProviderName() != "DatabaseProvider" ) {
            throw(
                type = "Megaphone.Configuration.InvalidChannelProvider",
                message = "Channel [#channel.getName()#] is not configured to use the `DatabaseProvider`.  Change the provider in your `megaphone` config struct."
            );
        }

        return variables.wirebox
            .getInstance( "DatabaseNotificationCursor@megaphone" )
            .setChannel( channel )
            .setQB( variables.wirebox.getInstance( "QueryBuilder@qb" ) )
            .setPage( arguments.initialPage )
            .setMaxRows( arguments.maxRows )
            .configureQuery( ( qb ) => {
                qb.from( channel.getTableName() )
                    .mergeDefaultOptions( channel.getQueryOptions() )
                    .whereNull( "readDate" )
                    .where( "notifiableId", notifiable.getNotifiableId() )
                    .where( "notifiableType", notifiable.getNotifiableType() );
            } )
            .fetch();
    }

}
