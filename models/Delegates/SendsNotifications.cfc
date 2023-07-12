component {

	property name="notificationService" inject="NotificationService@megaphone";

	public BaseNotification function notify( required any notification, struct properties = {} ) {
		return variables.notificationService.notify(
			$parent,
			arguments.notification,
			arguments.properties
		);
	}

}
