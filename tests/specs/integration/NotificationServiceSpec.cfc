component extends="tests.resources.ModuleIntegrationSpec" {

	property name="megaphone" inject="NotificationService@megaphone";

	function run() {
		describe( "notifications", () => {
			it( "can send a notification to a single notifiable", () => {
				var testNotifiable = {
					"getNotifiableId"   : () => 1,
					"getNotifiableType" : () => "test"
				};

				var notification = variables.megaphone.notify(
					testNotifiable,
					"SampleNotification",
					{}
				);

				var dbNotifications = getInstance( "QueryBuilder@qb" ).from( "megaphone_notifications" ).get();
				expect( dbNotifications ).toBeArray();
				expect( dbNotifications ).toHaveLength( 1 );
				var dbNotification = dbNotifications[ 1 ];
				expect( dbNotification.id ).notToBe( "" );
				expect( dbNotification.type ).toBe( notification.getNotificationType() );
				expect( dbNotification.notifiableId ).toBe( testNotifiable.getNotifiableId() );
				expect( dbNotification.notifiableType ).toBe( testNotifiable.getNotifiableType() );
				expect( dbNotification.data ).toBe( serializeJSON( { "foo" : "bar", "notifiable" : 1 } ) );
				expect( dbNotification.readDate ).toBe( "" );
				expect( dbNotification.createdDate ).notToBe( "" );
			} );

			it( "can send a notification to multiple notifiables", () => {
				var testNotifiableA = {
					"getNotifiableId"   : () => 1,
					"getNotifiableType" : () => "test"
				};
				var testNotifiableB = {
					"getNotifiableId"   : () => 2,
					"getNotifiableType" : () => "test"
				};

				var notification = variables.megaphone.notify(
					[ testNotifiableA, testNotifiableB ],
					getInstance( "SampleNotification" )
				);

				var dbNotifications = getInstance( "QueryBuilder@qb" )
					.from( "megaphone_notifications" )
					.orderBy( "notifiableId" )
					.get();
				expect( dbNotifications ).toBeArray();
				expect( dbNotifications ).toHaveLength( 2 );

				var dbNotification = dbNotifications[ 1 ];
				expect( dbNotification.id ).notToBe( "" );
				expect( dbNotification.type ).toBe( notification.getNotificationType() );
				expect( dbNotification.notifiableId ).toBe( testNotifiableA.getNotifiableId() );
				expect( dbNotification.notifiableType ).toBe( testNotifiableA.getNotifiableType() );
				expect( dbNotification.data ).toBe(
					serializeJSON( {
						"foo"        : "bar",
						"notifiable" : testNotifiableA.getNotifiableId()
					} )
				);
				expect( dbNotification.readDate ).toBe( "" );
				expect( dbNotification.createdDate ).notToBe( "" );

				var dbNotification = dbNotifications[ 2 ];
				expect( dbNotification.id ).notToBe( "" );
				expect( dbNotification.type ).toBe( notification.getNotificationType() );
				expect( dbNotification.notifiableId ).toBe( testNotifiableB.getNotifiableId() );
				expect( dbNotification.notifiableType ).toBe( testNotifiableB.getNotifiableType() );
				expect( dbNotification.data ).toBe(
					serializeJSON( {
						"foo"        : "bar",
						"notifiable" : testNotifiableB.getNotifiableId()
					} )
				);
				expect( dbNotification.readDate ).toBe( "" );
				expect( dbNotification.createdDate ).notToBe( "" );
			} );

			it( "throws an exception when trying to send a notification via an unknown channel", () => {
				var testNotifiable = {
					"getNotifiableId"   : () => 1,
					"getNotifiableType" : () => "test"
				};

				expect( () => {
					variables.megaphone.notify( testNotifiable, getInstance( "BadNotification" ) );
				} ).toThrow( type = "Megaphone.Configuration.MissingChannel" );
			} );
		} );
	}

}
