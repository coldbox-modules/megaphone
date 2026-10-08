component {

    property name="databaseNotificationService" inject="DatabaseNotificationService@megaphone";

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

    public any function getNotification(
        required string id,
        string channelName = "database",
        any constraints,
        string archiveMode = "all"
    ) {
        arguments.notifiable = $parent;
        return variables.databaseNotificationService.getNotification( argumentCollection = arguments );
    }

    public numeric function countUnreadNotifications(
        string channelName = "database",
        any constraints,
        string archiveMode = "all"
    ) {
        arguments.notifiable = $parent;
        return variables.databaseNotificationService.countUnreadNotifications( argumentCollection = arguments );
    }

    public array function snapshotIds( string channelName = "database", any constraints, string archiveMode = "all" ) {
        arguments.notifiable = $parent;
        return variables.databaseNotificationService.snapshotIds( argumentCollection = arguments );
    }

    public void function markSnapshotAsRead(
        required array ids,
        string channelName = "database",
        any constraints,
        date readDate = now()
    ) {
        arguments.notifiable = $parent;
        variables.databaseNotificationService.markSnapshotAsRead( argumentCollection = arguments );
    }

    public numeric function pruneNotifications(
        numeric keep = 1000,
        numeric batchSize = 200,
        string channelName = "database"
    ) {
        arguments.notifiable = $parent;
        return variables.databaseNotificationService.pruneNotifications( argumentCollection = arguments );
    }

}
