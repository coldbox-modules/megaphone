component extends="tests.resources.ModuleIntegrationSpec" {

	property name="databaseNotificationService" inject="DatabaseNotificationService@megaphone";
	property name="megaphone"                   inject="NotificationService@megaphone";

	function run() {
		describe( "has database notifications", () => {
			it( "can get all notifications for a notifiable", () => {
				var userA = getInstance( "User" ).setId( 1 );
				var userB = getInstance( "User" ).setId( 2 );

				variables.megaphone.notify( [ userA, userB ], getInstance( "SampleNotification" ) );
				userA.notify( getInstance( "SampleNotification" ) );

				var notificationsCursor = userA.getNotifications(
					channelName = "database",
					initialPage = 1,
					maxRows     = 1
				);
				expect( notificationsCursor ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( notificationsCursor.getPagination() ).toBe( {
					"maxRows"      : 1,
					"totalPages"   : 2,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 2
				} );
				expect( notificationsCursor.getResults() ).toBeArray();
				expect( notificationsCursor.getResults() ).toHaveLength( 1 );
				var notificationA = notificationsCursor.getResults()[ 1 ];
				expect( notificationA ).toBeInstanceOf( "megaphone.models.DatabaseNotification" );
				expect( notificationA.getData() ).toBe( {
					"foo"        : "bar",
					"notifiable" : userA.getNotifiableId()
				} );

				expect( notificationsCursor.hasPrevious() ).toBeFalse();
				expect( () => notificationsCursor.previous() ).toThrow(
					type = "Megaphone.DatabaseNotificationCursor.MinimumPageReached"
				);

				expect( notificationsCursor.hasNext() ).toBeTrue();
				notificationsCursor.next();

				expect( notificationsCursor.getPagination() ).toBe( {
					"maxRows"      : 1,
					"totalPages"   : 2,
					"offset"       : 1,
					"page"         : 2,
					"totalRecords" : 2
				} );
				expect( notificationsCursor.getResults() ).toBeArray();
				expect( notificationsCursor.getResults() ).toHaveLength( 1 );
				var notificationB = notificationsCursor.getResults()[ 1 ];
				expect( notificationB ).toBeInstanceOf( "megaphone.models.DatabaseNotification" );
				expect( notificationB.getData() ).toBe( {
					"foo"        : "bar",
					"notifiable" : userA.getNotifiableId()
				} );
				expect( notificationB.getId() ).notToBe( notificationA.getId() );

				expect( notificationsCursor.hasNext() ).toBeFalse();
				expect( () => notificationsCursor.next() ).toThrow(
					type = "Megaphone.DatabaseNotificationCursor.MaximumPageReached"
				);

				expect( notificationsCursor.hasPrevious() ).toBeTrue();
				notificationsCursor.previous();

				expect( notificationsCursor.getPagination() ).toBe( {
					"maxRows"      : 1,
					"totalPages"   : 2,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 2
				} );
				expect( notificationsCursor.getResults() ).toBeArray();
				expect( notificationsCursor.getResults() ).toHaveLength( 1 );
				var notificationAAgain = notificationsCursor.getResults()[ 1 ];
				expect( notificationAAgain ).toBeInstanceOf( "megaphone.models.DatabaseNotification" );
				expect( notificationAAgain.getId() ).toBe( notificationA.getId() );
			} );

			it( "can get all unread notifications for a notifiable", () => {
				var userA = getInstance( "User" ).setId( 1 );

				userA.notify( "SampleNotification" );
				userA.notify( "SampleNotification", {} );

				var notificationsCursor = variables.databaseNotificationService.getUnreadNotifications(
					userA,
					"database"
				);
				expect( notificationsCursor ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( notificationsCursor.getPagination() ).toBe( {
					"maxRows"      : 25,
					"totalPages"   : 1,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 2
				} );
				expect( notificationsCursor.getResults() ).toBeArray();
				expect( notificationsCursor.getResults() ).toHaveLength( 2 );
			} );

			it( "can get all read notifications for a notifiable", () => {
				var userA = getInstance( "User" ).setId( 1 );

				userA.notify( getInstance( "SampleNotification" ) );
				userA.notify( getInstance( "SampleNotification" ) );

				var notificationsCursor = userA.getReadNotifications( "database" );
				expect( notificationsCursor ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( notificationsCursor.getPagination() ).toBe( {
					"maxRows"      : 25,
					"totalPages"   : 0,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 0
				} );
				expect( notificationsCursor.getResults() ).toBeArray();
				expect( notificationsCursor.getResults() ).toHaveLength( 0 );
			} );

			it( "can mark a notification as read", () => {
				var userA = getInstance( "User" ).setId( 1 );

				userA.notify( getInstance( "SampleNotification" ) );
				userA.notify( getInstance( "SampleNotification" ) );

				var unreadNotificationsCursor = userA.getUnreadNotifications( "database" );
				expect( unreadNotificationsCursor ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( unreadNotificationsCursor.getPagination() ).toBe( {
					"maxRows"      : 25,
					"totalPages"   : 1,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 2
				} );
				expect( unreadNotificationsCursor.getResults() ).toBeArray();
				expect( unreadNotificationsCursor.getResults() ).toHaveLength( 2 );
				var notificationA = unreadNotificationsCursor.getResults()[ 1 ];
				var notificationB = unreadNotificationsCursor.getResults()[ 2 ];
				expect( notificationA ).toBeInstanceOf( "megaphone.models.DatabaseNotification" );
				expect( notificationB ).toBeInstanceOf( "megaphone.models.DatabaseNotification" );

				var readNotificationsCursor = userA.getReadNotifications( "database" );
				expect( readNotificationsCursor ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( readNotificationsCursor.getPagination() ).toBe( {
					"maxRows"      : 25,
					"totalPages"   : 0,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 0
				} );
				expect( readNotificationsCursor.getResults() ).toBeArray();
				expect( readNotificationsCursor.getResults() ).toHaveLength( 0 );

				notificationA.markAsRead();

				var unreadNotificationsCursorAgain = userA.getUnreadNotifications( "database" );
				expect( unreadNotificationsCursorAgain ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( unreadNotificationsCursorAgain.getPagination() ).toBe( {
					"maxRows"      : 25,
					"totalPages"   : 1,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 1
				} );
				expect( unreadNotificationsCursorAgain.getResults() ).toBeArray();
				expect( unreadNotificationsCursorAgain.getResults() ).toHaveLength( 1 );
				var notificationBAgain = unreadNotificationsCursorAgain.getResults()[ 1 ];
				expect( notificationB.getId() ).toBe( notificationBAgain.getId() );

				var readNotificationsCursorAgain = userA.getReadNotifications( "database" );
				expect( readNotificationsCursorAgain ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( readNotificationsCursorAgain.getPagination() ).toBe( {
					"maxRows"      : 25,
					"totalPages"   : 1,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 1
				} );
				expect( readNotificationsCursorAgain.getResults() ).toBeArray();
				expect( readNotificationsCursorAgain.getResults() ).toHaveLength( 1 );
				var notificationAAgain = readNotificationsCursorAgain.getResults()[ 1 ];
				expect( notificationA.getId() ).toBe( notificationAAgain.getId() );

				var allNotifications = userA.getNotifications( "database" );
				expect( allNotifications ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( allNotifications.getPagination() ).toBe( {
					"maxRows"      : 25,
					"totalPages"   : 1,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 2
				} );
				expect( allNotifications.getResults() ).toBeArray();
				expect( allNotifications.getResults() ).toHaveLength( 2 );
				expect( allNotifications.getResults()[ 1 ].getId() ).toBe( notificationA.getId() );
				expect( allNotifications.getResults()[ 2 ].getId() ).toBe( notificationB.getId() );
			} );

			it( "can delete a notification", () => {
				var userA = getInstance( "User" ).setId( 1 );

				userA.notify( getInstance( "SampleNotification" ) );
				userA.notify( getInstance( "SampleNotification" ) );

				var unreadNotificationsCursor = userA.getUnreadNotifications();
				expect( unreadNotificationsCursor ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( unreadNotificationsCursor.getPagination() ).toBe( {
					"maxRows"      : 25,
					"totalPages"   : 1,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 2
				} );
				expect( unreadNotificationsCursor.getResults() ).toBeArray();
				expect( unreadNotificationsCursor.getResults() ).toHaveLength( 2 );
				var notificationA = unreadNotificationsCursor.getResults()[ 1 ];
				var notificationB = unreadNotificationsCursor.getResults()[ 2 ];
				expect( notificationA ).toBeInstanceOf( "megaphone.models.DatabaseNotification" );
				expect( notificationB ).toBeInstanceOf( "megaphone.models.DatabaseNotification" );

				var readNotificationsCursor = userA.getReadNotifications();
				expect( readNotificationsCursor ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( readNotificationsCursor.getPagination() ).toBe( {
					"maxRows"      : 25,
					"totalPages"   : 0,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 0
				} );
				expect( readNotificationsCursor.getResults() ).toBeArray();
				expect( readNotificationsCursor.getResults() ).toBeEmpty();

				notificationA.delete();

				var unreadNotificationsCursorAgain = userA.getUnreadNotifications();
				expect( unreadNotificationsCursorAgain ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( unreadNotificationsCursorAgain.getPagination() ).toBe( {
					"maxRows"      : 25,
					"totalPages"   : 1,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 1
				} );
				expect( unreadNotificationsCursorAgain.getResults() ).toBeArray();
				expect( unreadNotificationsCursorAgain.getResults() ).toHaveLength( 1 );
				var notificationBAgain = unreadNotificationsCursorAgain.getResults()[ 1 ];
				expect( notificationB.getId() ).toBe( notificationBAgain.getId() );

				var readNotificationsCursorAgain = userA.getReadNotifications();
				expect( readNotificationsCursorAgain ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( readNotificationsCursorAgain.getPagination() ).toBe( {
					"maxRows"      : 25,
					"totalPages"   : 0,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 0
				} );
				expect( readNotificationsCursorAgain.getResults() ).toBeArray();
				expect( readNotificationsCursorAgain.getResults() ).toBeEmpty();

				var allNotifications = userA.getNotifications();
				expect( allNotifications ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( allNotifications.getPagination() ).toBe( {
					"maxRows"      : 25,
					"totalPages"   : 1,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 1
				} );
				expect( allNotifications.getResults() ).toBeArray();
				expect( allNotifications.getResults() ).toHaveLength( 1 );
				expect( allNotifications.getResults()[ 1 ].getId() ).toBe( notificationB.getId() );
			} );

			it( "can mark all notifications as read", () => {
				var userA = getInstance( "User" ).setId( 1 );

				userA.notify( getInstance( "SampleNotification" ) );
				userA.notify( getInstance( "SampleNotification" ) );

				var notificationsCursor = userA.getUnreadNotifications(
					channelName = "database",
					initialPage = 1,
					maxRows     = 1
				);
				expect( notificationsCursor ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( notificationsCursor.getPagination() ).toBe( {
					"maxRows"      : 1,
					"totalPages"   : 2,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 2
				} );
				expect( notificationsCursor.getResults() ).toHaveLength( 1 );

				notificationsCursor.markAllAsRead();

				var notificationsCursorAgain = userA.getUnreadNotifications(
					channelName = "database",
					initialPage = 1,
					maxRows     = 1
				);
				expect( notificationsCursorAgain ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( notificationsCursorAgain.getPagination() ).toBe( {
					"maxRows"      : 1,
					"totalPages"   : 0,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 0
				} );
				expect( notificationsCursorAgain.getResults() ).toBeEmpty();
			} );

			it( "can delete all notifications as read", () => {
				var userA = getInstance( "User" ).setId( 1 );

				userA.notify( getInstance( "SampleNotification" ) );
				userA.notify( getInstance( "SampleNotification" ) );

				var notificationsCursor = userA.getUnreadNotifications(
					channelName = "database",
					initialPage = 1,
					maxRows     = 1
				);
				expect( notificationsCursor ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( notificationsCursor.getPagination() ).toBe( {
					"maxRows"      : 1,
					"totalPages"   : 2,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 2
				} );
				expect( notificationsCursor.getResults() ).toHaveLength( 1 );

				notificationsCursor.deleteAll();

				var notificationsCursorAgain = userA.getUnreadNotifications(
					channelName = "database",
					initialPage = 1,
					maxRows     = 1
				);
				expect( notificationsCursorAgain ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( notificationsCursorAgain.getPagination() ).toBe( {
					"maxRows"      : 1,
					"totalPages"   : 0,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 0
				} );
				expect( notificationsCursorAgain.getResults() ).toBeEmpty();

				var readNotificationsCursor = userA.getReadNotifications(
					channelName = "database",
					initialPage = 1,
					maxRows     = 1
				);
				expect( readNotificationsCursor ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( readNotificationsCursor.getPagination() ).toBe( {
					"maxRows"      : 1,
					"totalPages"   : 0,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 0
				} );
				expect( readNotificationsCursor.getResults() ).toBeEmpty();

				var allNotificationsCursor = userA.getNotifications(
					channelName = "database",
					initialPage = 1,
					maxRows     = 1
				);
				expect( allNotificationsCursor ).toBeInstanceOf( "megaphone.models.DatabaseNotificationCursor" );
				expect( allNotificationsCursor.getPagination() ).toBe( {
					"maxRows"      : 1,
					"totalPages"   : 0,
					"offset"       : 0,
					"page"         : 1,
					"totalRecords" : 0
				} );
				expect( allNotificationsCursor.getResults() ).toBeEmpty();
			} );
		} );
	}

}
