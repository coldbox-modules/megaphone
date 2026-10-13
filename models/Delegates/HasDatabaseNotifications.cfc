component {

    property name="databaseNotificationService" inject="DatabaseNotificationService@megaphone";

    /**
     * Loads a forward-only page after a recipient-bound timestamp/ID cursor.
     * @returns DatabaseNotificationKeysetCursor
     */
    public DatabaseNotificationKeysetCursor function getNotificationsAfter(
        string channelName = "database",
        string afterCursor = "",
        numeric maxRows = 25,
        any constraints,
        string archiveMode = "active",
        boolean unread = false
    ) {
        arguments.notifiable = $parent;
        return variables.databaseNotificationService.getNotificationsAfter( argumentCollection = arguments );
    }

    /**
     * Returns all database notifications for a Notifiable.
     * @returns DatabaseNotificationCursor
     */
    public DatabaseNotificationCursor function getNotifications(
        string channelName = "database",
        numeric initialPage = 1,
        numeric maxRows = 25,
        any constraints,
        string archiveMode = "all"
    ) {
        arguments.notifiable = $parent;
        return variables.databaseNotificationService.getNotifications( argumentCollection = arguments );
    }

    /**
     * Returns all read database notifications for a Notifiable.
     * @returns DatabaseNotificationCursor
     */
    public DatabaseNotificationCursor function getReadNotifications(
        string channelName = "database",
        numeric initialPage = 1,
        numeric maxRows = 25,
        any constraints,
        string archiveMode = "all"
    ) {
        arguments.notifiable = $parent;
        return variables.databaseNotificationService.getReadNotifications( argumentCollection = arguments );
    }

    /**
     * Returns all unread database notifications for a Notifiable.
     * @returns DatabaseNotificationCursor
     */
    public DatabaseNotificationCursor function getUnreadNotifications(
        string channelName = "database",
        numeric initialPage = 1,
        numeric maxRows = 25,
        any constraints,
        string archiveMode = "all"
    ) {
        arguments.notifiable = $parent;
        return variables.databaseNotificationService.getUnreadNotifications( argumentCollection = arguments );
    }

    /**
     * Finds one owned, currently authorized notification, or returns null.
     * @returns any
     */
    public any function getNotification(
        required string id,
        string channelName = "database",
        any constraints,
        string archiveMode = "all"
    ) {
        arguments.notifiable = $parent;
        return variables.databaseNotificationService.getNotification( argumentCollection = arguments );
    }

    /**
     * Counts unread notifications after applying ownership and authorization constraints.
     * @returns numeric
     */
    public numeric function countUnreadNotifications(
        string channelName = "database",
        any constraints,
        string archiveMode = "all"
    ) {
        arguments.notifiable = $parent;
        return variables.databaseNotificationService.countUnreadNotifications( argumentCollection = arguments );
    }

    /**
     * Captures the currently matching, authorized inbox IDs without a page limit.
     * @returns array
     */
    public array function snapshotIds( string channelName = "database", any constraints, string archiveMode = "all" ) {
        arguments.notifiable = $parent;
        return variables.databaseNotificationService.snapshotIds( argumentCollection = arguments );
    }

    /**
     * Marks captured IDs only when they remain owned, authorized, and unread; later arrivals are excluded.
     */
    public void function markSnapshotAsRead(
        required array ids,
        string channelName = "database",
        any constraints,
        date readDate = now()
    ) {
        arguments.notifiable = $parent;
        variables.databaseNotificationService.markSnapshotAsRead( argumentCollection = arguments );
    }

    /**
     * Deletes a bounded batch of the oldest owned inbox entries beyond the retention cap.
     * @returns numeric
     */
    public numeric function pruneNotifications(
        numeric keep = 1000,
        numeric batchSize = 200,
        string channelName = "database"
    ) {
        arguments.notifiable = $parent;
        return variables.databaseNotificationService.pruneNotifications( argumentCollection = arguments );
    }

}
