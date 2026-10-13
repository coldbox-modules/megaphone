component accessors="true" {

    property name="channel";
    property name="qb";
    property name="mutationQuery";

    property name="page";
    property name="maxRows";
    property name="results";
    property name="pagination";

    /**
     * Applies query constraints; display-only filters can leave mutation authorization unchanged.
     * @returns DatabaseNotificationCursor
     */
    public DatabaseNotificationCursor function configureQuery(
        required function callback,
        boolean constrainMutations = true
    ) {
        arguments.callback( variables.qb );
        if ( arguments.constrainMutations && !isNull( variables.mutationQuery ) ) {
            arguments.callback( variables.mutationQuery );
        }
        return this;
    }

    /**
     * Loads the current numbered page and wraps its rows as DatabaseNotification objects.
     * @returns DatabaseNotificationCursor
     */
    public DatabaseNotificationCursor function fetch() {
        var res = variables.qb
            .clone()
            .orderByDesc( "createdDate" )
            .orderByDesc( "id" )
            .paginate( variables.page, variables.maxRows );
        variables.pagination = res.pagination;
        variables.results = res.results.map( ( row ) => {
            return newMegaphoneDatabaseNotification()
                .setChannel( getChannel() )
                .setMutationQuery(
                    !isNull( variables.mutationQuery ) ? variables.mutationQuery.clone() : variables.qb.clone()
                )
                .populateFromDatabaseRow( row );
        } );
        return this;
    }

    /**
     * Checks whether another page is available.
     * @returns boolean
     */
    public boolean function hasNext() {
        return variables.page < variables.pagination.totalPages;
    }

    /**
     * Loads the next page and returns this cursor.
     * @returns DatabaseNotificationCursor
     */
    public DatabaseNotificationCursor function next() {
        if ( variables.page == variables.pagination.totalPages ) {
            throw(
                type = "Megaphone.DatabaseNotificationCursor.MaximumPageReached",
                message = "You are already on the last page of results.  Check the `hasNext` method before calling `next` to avoid this exception.",
                extendedInfo = serializeJSON( variables.pagination )
            );
        }

        variables.page++;
        fetch();
        return this;
    }

    /**
     * Checks whether a previous numbered page is available.
     * @returns boolean
     */
    public boolean function hasPrevious() {
        return variables.page > 1;
    }

    /**
     * Loads the previous numbered page and returns this cursor.
     * @returns DatabaseNotificationCursor
     */
    public DatabaseNotificationCursor function previous() {
        if ( variables.page == 1 ) {
            throw(
                type = "Megaphone.DatabaseNotificationCursor.MinimumPageReached",
                message = "You are already on the first page of results.  Check the `hasPrevious` method before calling `previous` to avoid this exception.",
                extendedInfo = serializeJSON( variables.pagination )
            );
        }

        variables.page--;
        fetch();
        return this;
    }

    /**
     * Replaces the read timestamp on every notification matching this cursor.
     * @returns DatabaseNotificationCursor
     */
    public DatabaseNotificationCursor function markAllAsRead( date readDate = now() ) {
        variables.qb.clone().update( { "readDate": arguments.readDate } );
        return this;
    }

    /**
     * Marks matching unread notifications without replacing their first read timestamp.
     * @returns DatabaseNotificationCursor
     */
    public DatabaseNotificationCursor function markAllAsReadIfUnread( date readDate = now() ) {
        variables.qb
            .clone()
            .whereNull( "readDate" )
            .update( { "readDate": arguments.readDate } );
        return this;
    }

    /**
     * Deletes every notification matching this cursor.
     * @returns DatabaseNotificationCursor
     */
    public DatabaseNotificationCursor function deleteAll() {
        variables.qb.clone().delete();
        return this;
    }

    /**
     * Supplies a fresh DatabaseNotification through WireBox.
     * @returns DatabaseNotification
     */
    private DatabaseNotification function newMegaphoneDatabaseNotification() provider="DatabaseNotification@megaphone" {
    }

}
