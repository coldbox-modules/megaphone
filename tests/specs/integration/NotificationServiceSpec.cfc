component extends="tests.resources.ModuleIntegrationSpec" {

    property name="megaphone" inject="NotificationService@megaphone";

    function run() {
        describe( "notifications", () => {
            it( "can send a notification to a single notifiable", () => {
                var testNotifiable = { "getNotifiableId": () => 1, "getNotifiableType": () => "test" };

                var notification = variables.megaphone.notify( testNotifiable, "SampleNotification", {} );

                var dbNotifications = getInstance( "QueryBuilder@qb" ).from( "megaphone_notifications" ).get();
                expect( dbNotifications ).toBeArray();
                expect( dbNotifications ).toHaveLength( 1 );
                var dbNotification = dbNotifications[ 1 ];
                expect( dbNotification.id ).notToBe( "" );
                expect( dbNotification.type ).toBe( notification.getNotificationType() );
                expect( dbNotification.notifiableId ).toBe( testNotifiable.getNotifiableId() );
                expect( dbNotification.notifiableType ).toBe( testNotifiable.getNotifiableType() );
                expect( dbNotification.data ).toBe( serializeJSON( { "foo": "bar", "notifiable": 1 } ) );
                expect( isNull( dbNotification.readDate ) || dbNotification.readDate == "" ).toBeTrue();
                expect( dbNotification.createdDate ).notToBe( "" );
            } );

            it( "can send a notification to multiple notifiables", () => {
                var testNotifiableA = { "getNotifiableId": () => 1, "getNotifiableType": () => "test" };
                var testNotifiableB = { "getNotifiableId": () => 2, "getNotifiableType": () => "test" };

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
                    serializeJSON( { "foo": "bar", "notifiable": testNotifiableA.getNotifiableId() } )
                );
                expect( isNull( dbNotification.readDate ) || dbNotification.readDate == "" ).toBeTrue();
                expect( dbNotification.createdDate ).notToBe( "" );

                var dbNotification = dbNotifications[ 2 ];
                expect( dbNotification.id ).notToBe( "" );
                expect( dbNotification.type ).toBe( notification.getNotificationType() );
                expect( dbNotification.notifiableId ).toBe( testNotifiableB.getNotifiableId() );
                expect( dbNotification.notifiableType ).toBe( testNotifiableB.getNotifiableType() );
                expect( dbNotification.data ).toBe(
                    serializeJSON( { "foo": "bar", "notifiable": testNotifiableB.getNotifiableId() } )
                );
                expect( isNull( dbNotification.readDate ) || dbNotification.readDate == "" ).toBeTrue();
                expect( dbNotification.createdDate ).notToBe( "" );
            } );

            it( "deep-copies notification data per recipient while retaining WireBox provider access", () => {
                var first = { "getNotifiableId": () => 1, "getNotifiableType": () => "test" };
                var second = { "getNotifiableId": () => 2, "getNotifiableType": () => "test" };
                var original = getInstance( "MutableDataNotification" ).setId( "original" );
                var returned = variables.megaphone.notify(
                    [ first, second ],
                    original,
                    { "payload": { "history": [] } }
                );
                var rows = getInstance( "QueryBuilder@qb" )
                    .from( "megaphone_notifications" )
                    .orderBy( "notifiableId" )
                    .get();
                expect( rows ).toHaveLength( 2 );
                expect( deserializeJSON( rows[ 1 ].data ).history ).toBe( [ 1 ] );
                expect( deserializeJSON( rows[ 2 ].data ).history ).toBe( [ 2 ] );
                expect( rows[ 1 ].id ).notToBe( rows[ 2 ].id );
                expect( rows[ 1 ].id ).notToBe( "original" );
                expect( original.getPayload().history ).toBeEmpty();
                expect(
                    original
                        .getNotificationService()
                        .getChannel( "database" )
                        .getName()
                ).toBe( "database" );
                expect( returned.getId() ).toBe( "original" );
            } );

            it( "throws an exception when trying to send a notification via an unknown channel", () => {
                var testNotifiable = { "getNotifiableId": () => 1, "getNotifiableType": () => "test" };

                expect( () => {
                    variables.megaphone.notify( testNotifiable, getInstance( "BadNotification" ) );
                } ).toThrow( type = "Megaphone.Configuration.MissingChannel" );
            } );
        } );
    }

}
