/** Optional SDK integration bundle. Run InstallWebPushSDK before invoking this bundle. No network sends. */
component extends="testbox.system.BaseSpec" {

    function run() {
        if ( val( createObject( "java", "java.lang.System" ).getProperty( "java.specification.version" ) ) < 11 ) {
            xdescribe( "Web Push SDK requires Java 11", () => {
            } );
            return;
        }
        describe( "Real Web Push request preparation", () => {
            beforeEach( () => {
                variables.factory = new tests.resources.PushSDKClassFactory(
                    expandPath( "/megaphone/resources/java/webpush/zerodep-web-push-java-2.1.5.jar" )
                );
                var generator = createObject( "java", "java.security.KeyPairGenerator" ).getInstance( "EC" );
                generator.initialize(
                    createObject( "java", "java.security.spec.ECGenParameterSpec" ).init( "secp256r1" )
                );
                var vapid = generator.generateKeyPair();
                variables.keyPair = variables.factory
                    .create( "com.zerodeplibs.webpush.VAPIDKeyPairs" )
                    .of(
                        variables.factory
                            .create( "com.zerodeplibs.webpush.key.PrivateKeySources" )
                            .ofECPrivateKey( vapid.getPrivate() ),
                        variables.factory
                            .create( "com.zerodeplibs.webpush.key.PublicKeySources" )
                            .ofECPublicKey( vapid.getPublic() )
                    );
                variables.transport = new megaphone.models.WebPushTransport(
                    classFactory = variables.factory,
                    vapidKeyPair = variables.keyPair,
                    subject = "mailto:push@example.test",
                    allowedHosts = [ "push.example.test", "*.push.example.test" ]
                );
                var receiver = generator.generateKeyPair().getPublic();
                var classes = createObject( "java", "java.lang.Class" );
                var noTypes = createObject( "java", "java.lang.reflect.Array" ).newInstance(
                    classes.forName( "java.lang.Class" ),
                    javacast( "int", 0 )
                );
                var point = classes
                    .forName( "java.security.interfaces.ECPublicKey" )
                    .getMethod( "getW", noTypes )
                    .invoke(
                        receiver,
                        createObject( "java", "java.lang.reflect.Array" ).newInstance(
                            classes.forName( "java.lang.Object" ),
                            javacast( "int", 0 )
                        )
                    );
                var x = coordinate( point.getAffineX() );
                var y = coordinate( point.getAffineY() );
                variables.subscription = {
                    "endpoint": "https://push.example.test/subscription/private-id",
                    "keys": {
                        "p256dh": base64url( binaryDecode( "04" & x & y, "hex" ) ),
                        "auth": base64url( binaryDecode( repeatString( "01", 16 ), "hex" ) )
                    }
                };
            } );
            it( "builds an encrypted, authenticated POST with bounded timing", () => {
                var preparedRequest = variables.transport.prepare(
                    variables.subscription,
                    { "title": "New audition", "body": "Private preview" },
                    120
                );
                var bridge = new megaphone.models.JavaHttpBridge();
                expect( bridge.requestValue( preparedRequest, "method" ) ).toBe( "POST" );
                expect( bridge.requestValue( preparedRequest, "uri" ).toString() ).toBe(
                    variables.subscription.endpoint
                );
                expect(
                    bridge
                        .requestValue( preparedRequest, "headers" )
                        .firstValue( "Content-Encoding" )
                        .orElse( "" )
                ).toBe( "aes128gcm" );
                expect(
                    bridge
                        .requestValue( preparedRequest, "headers" )
                        .firstValue( "Authorization" )
                        .orElse( "" )
                ).toInclude( "vapid " );
                expect(
                    bridge
                        .requestValue( preparedRequest, "headers" )
                        .firstValue( "TTL" )
                        .orElse( "" )
                ).toBe( "120" );
                expect(
                    bridge
                        .requestValue( preparedRequest, "timeout" )
                        .get()
                        .getSeconds()
                ).toBe( 10 );
                expect( bridge.bodyLength( preparedRequest ) ).toBeGT( 103 );
            } );
            it( "rejects alternate schemes, ports, credentials, fragments, and host lookalikes", () => {
                for (
                    var endpoint in [
                        "http://push.example.test/x",
                        "https://push.example.test:444/x",
                        "https://user@push.example.test/x",
                        "https://push.example.test/x##secret",
                        "https://push.example.test.attacker.test/x",
                        "https://127.0.0.1/x"
                    ]
                ) {
                    expect( () => variables.transport.validateEndpoint( endpoint ) ).toThrow(
                        type = "Megaphone.Push.InvalidEndpoint"
                    );
                }
                variables.transport.validateEndpoint( "https://region.push.example.test/x" );
            } );
            it( "rejects invalid key material and oversized UTF-8 payloads before sending", () => {
                var invalid = duplicate( variables.subscription );
                invalid.keys.auth = "wrong";
                expect( () => variables.transport.prepare( invalid, { "title": "test" } ) ).toThrow(
                    type = "Megaphone.Push.InvalidRequest"
                );
                expect( () => variables.transport.prepare( variables.subscription, { "body": repeatString( "x", 4000 ) } ) ).toThrow(
                    type = "Megaphone.Push.InvalidRequest"
                );
                expect( () => variables.transport.prepare( variables.subscription, {}, -1 ) ).toThrow(
                    type = "Megaphone.Push.InvalidRequest"
                );
            } );
            it( "sends one prepared request and returns acceptance without leaking endpoint data", () => {
                var httpFixture = new tests.resources.PushHttpClientFixture( code = 201 );
                var transport = fixtureTransport( httpFixture );
                var outcome = transport.sendPrepared( transport.prepare( variables.subscription, { "title": "test" } ) );
                expect( outcome.outcome ).toBe( "accepted" );
                expect( httpFixture.getCalls() ).toBe( 1 );
                expect( serializeJSON( outcome ) ).notToInclude( "private-id" );
            } );
            it( "keeps one expired device and retryable service responses distinct", () => {
                var expired = fixtureTransport( new tests.resources.PushHttpClientFixture( code = 410 ) );
                var result = expired.sendPrepared( expired.prepare( variables.subscription, {} ) );
                expect( result.retireSubscription ).toBeTrue();
                var busy = fixtureTransport(
                    new tests.resources.PushHttpClientFixture( code = 429, retryAfter = "120" )
                );
                result = busy.sendPrepared( busy.prepare( variables.subscription, {} ) );
                expect( result.outcome ).toBe( "retryable" );
                expect( isDate( result.retryDate ) ).toBeTrue();
            } );
            it( "does not automatically retry transport exceptions or expose their details", () => {
                var httpFixture = new tests.resources.PushHttpClientFixture( fail = true );
                var transport = fixtureTransport( httpFixture );
                var result = transport.sendPrepared( transport.prepare( variables.subscription, {} ) );
                expect( result.outcome ).toBe( "ambiguous" );
                expect( httpFixture.getCalls() ).toBe( 1 );
                expect( serializeJSON( result ) ).notToInclude( "fixture-secret" );
            } );
        } );
    }

    private string function coordinate( required any integer ) {
        var encoded = arguments.integer.toString( javacast( "int", 16 ) );
        return repeatString( "0", 64 - len( encoded ) ) & encoded;
    }
    private any function fixtureTransport( required any client ) {
        return new megaphone.models.WebPushTransport(
            classFactory = variables.factory,
            vapidKeyPair = variables.keyPair,
            subject = "mailto:push@example.test",
            allowedHosts = [ "push.example.test" ],
            httpClient = arguments.client
        );
    }
    private string function base64url( required any bytes ) {
        return createObject( "java", "java.util.Base64" )
            .getUrlEncoder()
            .withoutPadding()
            .encodeToString( arguments.bytes );
    }

}
