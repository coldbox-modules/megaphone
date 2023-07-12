component {

	property name="databaseNotificationService" inject="DatabaseNotificationService@megaphone";

	/**
	 * Returns all database notifications for a Notifiable.
	 * @returns DatabaseNotificationCursor
	 */
	public DatabaseNotificationCursor function getNotifications(
		string channelName  = "database",
		numeric initialPage = 1,
		numeric maxRows     = 25
	) {
		arguments.notifiable = $parent;
		return variables.databaseNotificationService.getNotifications( argumentCollection = arguments );
	}

	/**
	 * Returns all read database notifications for a Notifiable.
	 * @returns DatabaseNotificationCursor
	 */
	public DatabaseNotificationCursor function getReadNotifications(
		string channelName  = "database",
		numeric initialPage = 1,
		numeric maxRows     = 25
	) {
		arguments.notifiable = $parent;
		return variables.databaseNotificationService.getReadNotifications( argumentCollection = arguments );
	}

	/**
	 * Returns all unread database notifications for a Notifiable.
	 * @returns DatabaseNotificationCursor
	 */
	public DatabaseNotificationCursor function getUnreadNotifications(
		string channelName  = "database",
		numeric initialPage = 1,
		numeric maxRows     = 25
	) {
		arguments.notifiable = $parent;
		return variables.databaseNotificationService.getUnreadNotifications( argumentCollection = arguments );
	}

}
