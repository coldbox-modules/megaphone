component extends="tests.resources.ModuleIntegrationSpec" {

    function run() {
        describe( "Application overrides for Megaphone models", () => {
            beforeEach( () => {
                var binder = getWireBox().getBinder();
                for ( var name in [ "NotificationPlan", "NotificationEvent", "SubscriptionCipher" ] ) {
                    binder
                        .map( name & "@megaphone" )
                        .to( "tests.resources.Mapped" & name )
                        .initArg( name = "marker", value = "from-wirebox" );
                }
                binder.map( "QueueNotification" ).to( "tests.resources.QueueNotification" );
            } );
            afterEach( () => {
                for ( var name in [ "NotificationPlan", "NotificationEvent", "SubscriptionCipher" ] ) {
                    getWireBox()
                        .getBinder()
                        .map( name & "@megaphone" )
                        .to( "megaphone.models." & name );
                }
            } );
            it( "preserves injected constructors while planning and wrapping saved events", () => {
                var service = getWireBox().getInstance( "NotificationService@megaphone" );
                var plan = service.plan(
                    new tests.resources.InboxRecipient(),
                    "QueueNotification",
                    { "message": "captured" },
                    { "eventKey": createUUID() }
                );
                expect( plan.suppliedByTestMapping() ).toBeTrue();
                expect( plan.getEvent().payload.message ).toBe( "captured" );
                var operations = getWireBox().getInstance( "NotificationDeliveryService@megaphone" );
                var savedEvent = operations.recordEvent( argumentCollection = plan.getEvent() );
                expect( savedEvent.suppliedByTestMapping() ).toBeTrue();
                expect( savedEvent.getCreated() ).toBeTrue();
                var loadedEvent = operations.getEvent( savedEvent.getId() );
                expect( loadedEvent.suppliedByTestMapping() ).toBeTrue();
                expect( loadedEvent.getPayload() ).toBe( plan.getEvent().payload );
            } );
            it( "configures an overridden cipher without replacing its constructor dependency", () => {
                var key = binaryEncode( binaryDecode( repeatString( "01", 32 ), "hex" ), "base64" );
                var runtime = getWireBox().getInstance(
                    name = "WebPushRuntime@megaphone",
                    initArguments = { "properties": { "activeStorageKeyId": "one", "storageKeys": { "one": key } } }
                );
                var cipher = runtime.cipher();
                expect( cipher.suppliedByTestMapping() ).toBeTrue();
                var subscription = { "endpoint": "https://push.example.test/owned", "keys": { "auth": "secret" } };
                var sealed = cipher.seal( subscription, "user|42|example.test" );
                expect( cipher.unseal( sealed, "user|42|example.test" ) ).toBe( subscription );
                expect( () => cipher.unseal( sealed, "user|other|example.test" ) ).toThrow( "Megaphone.Push.InvalidSealedData" );
            } );
        } );
    }

}
