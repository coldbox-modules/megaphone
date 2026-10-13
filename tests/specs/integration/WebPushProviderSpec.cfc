component extends="tests.specs.integration.NotificationQueueSpec" {

    function beforeAll() {
        super.beforeAll();
        variables.injector = getWireBox();
        variables.injector
            .getBinder()
            .map( "QueuePushNotification" )
            .to( "tests.resources.QueuePushNotification" );
        variables.subscriptions = variables.injector.getInstance( "PushSubscriptionService@megaphone" );
    }
    function run() {
        if ( val( createObject( "java", "java.lang.System" ).getProperty( "java.specification.version" ) ) < 11 ) {
            xdescribe( "Registered Web Push requires Java 11", () => {
            } );
            return;
        }
        describe( "Registered Web Push provider and sealed subscription service", () => {
            beforeEach( () => {
                variables.owner = new tests.resources.InboxRecipient();
                variables.resolver.register( variables.owner );
                variables.policy.setStatus( "ready" );
                variables.http = new tests.resources.PushHttpClientFixture();
                var generator = createObject( "java", "java.security.KeyPairGenerator" ).getInstance( "EC" );
                generator.initialize(
                    createObject( "java", "java.security.spec.ECGenParameterSpec" ).init( "secp256r1" )
                );
                var pair = generator.generateKeyPair();
                variables.properties = {
                    "enabled": true,
                    "origin": "https://app.example.test",
                    "subject": "mailto:push@example.test",
                    "allowedHosts": [ "push.example.test" ],
                    "activeStorageKeyId": "test",
                    "storageKeys": { "test": binaryEncode( binaryDecode( repeatString( "01", 32 ), "hex" ), "base64" ) },
                    "publicKey": binaryEncode( pair.getPublic().getEncoded(), "base64" ),
                    "privateKey": binaryEncode( pair.getPrivate().getEncoded(), "base64" ),
                    "httpClient": variables.http
                };
                var classes = createObject( "java", "java.lang.Class" );
                var noTypes = createObject( "java", "java.lang.reflect.Array" ).newInstance(
                    classes.forName( "java.lang.Class" ),
                    javacast( "int", 0 )
                );
                var point = classes
                    .forName( "java.security.interfaces.ECPublicKey" )
                    .getMethod( "getW", noTypes )
                    .invoke( generator.generateKeyPair().getPublic(), javacast( "object[]", [] ) );
                variables.subscription = {
                    "endpoint": "https://push.example.test/subscription/test",
                    "keys": {
                        "p256dh": base64url(
                            binaryDecode(
                                "04" & right( repeatString( "0", 64 ) & point.getAffineX().toString( 16 ), 64 ) & right(
                                    repeatString( "0", 64 ) & point.getAffineY().toString( 16 ),
                                    64
                                ),
                                "hex"
                            )
                        ),
                        "auth": base64url( binaryDecode( repeatString( "02", 16 ), "hex" ) )
                    }
                };
                variables.service.registerChannels( { "push": { "provider": "WebPushProvider@megaphone", "properties": variables.properties } } );
                getController().getSetting( "moduleSettings" ).megaphone.queue.queueAdapter = "";
            } );
            it( "seals and renews owned subscriptions without changing preferences or exposing secrets", () => {
                var first = variables.subscriptions.register( variables.owner, variables.subscription, "Browser" );
                variables.subscriptions.setExcluded(
                    variables.owner,
                    "QueuePushNotification",
                    first.id,
                    true
                );
                var renewed = variables.subscriptions.register(
                    variables.owner,
                    variables.subscription,
                    "Browser",
                    first.id
                );
                expect( renewed.id ).toBe( first.id );
                expect( serializeJSON( renewed ) ).notToInclude( "sealedData" );
                expect( serializeJSON( renewed ) ).notToInclude( "endpointHash" );
                expect( variables.subscriptions.getExcludedIds( variables.owner, "QueuePushNotification" ) ).toBe( [ first.id ] );
                expect( variables.http.getCalls() ).toBe( 0 );
            } );
            it( "sends through the registered provider once and retires only an expired destination", () => {
                var first = variables.subscriptions.register( variables.owner, variables.subscription, "Browser" );
                var published = variables.service.queue( variables.owner, "QueuePushNotification" );
                var work = published.getDeliveries()[ 1 ];
                expect( work.getDeviceId() ).toBe( first.id );
                expect( variables.deliveries.dispatch( work.getId() ).getStatus() ).toBe( "accepted" );
                expect( variables.deliveries.dispatch( work.getId() ).getStatus() ).toBe( "accepted" );
                expect( variables.http.getCalls() ).toBe( 1 );
                var expired = new tests.resources.PushHttpClientFixture( 410 );
                variables.properties.httpClient = expired;
                var next = variables.service.queue( variables.owner, "QueuePushNotification" ).getDeliveries()[ 1 ];
                expect( variables.deliveries.dispatch( next.getId() ).getStatus() ).toBe( "permanent" );
                expect( variables.subscriptions.getRegistrations( variables.owner ) ).toBeEmpty();
                expect( expired.getCalls() ).toBe( 1 );
            } );
            it( "retires an expired device without retiring another owned registration", () => {
                var expired = variables.subscriptions.register(
                    notifiable = variables.owner,
                    subscription = variables.subscription,
                    label = "Expired",
                    expiresDate = dateAdd( "h", -1, now() )
                );
                var other = duplicate( variables.subscription );
                other.endpoint &= "/active";
                var active = variables.subscriptions.register( variables.owner, other, "Active" );
                expect( variables.subscriptions.retireExpired( variables.owner ) ).toBe( 1 );
                expect( variables.subscriptions.getRegistrations( variables.owner ).map( ( device ) => device.id ) ).toBe( [ active.id ] );
                expect(
                    variables.subscriptions
                        .getRegistrations( variables.owner, false )
                        .filter( ( device ) => device.id == expired.id )[ 1 ].active
                ).toBeFalse();
            } );
            it( "does not enqueue a phantom push when no destination is eligible", () => {
                var published = variables.service.queue( variables.owner, "QueuePushNotification" );
                expect( published.getDeliveries()[ 1 ].getState() ).toBe( "suppressed" );
                expect( published.getDeliveries()[ 1 ].getDeviceId() ).toBe( "" );
                expect( variables.http.getCalls() ).toBe( 0 );
            } );
        } );
    }
    private string function base64url( required binary bytes ) {
        return reReplace(
            replace(
                replace(
                    binaryEncode( arguments.bytes, "base64" ),
                    "+",
                    "-",
                    "all"
                ),
                "/",
                "_",
                "all"
            ),
            "=+$",
            ""
        );
    }

}
