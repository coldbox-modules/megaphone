/** Explicit deployment keys; disabling push keeps unrelated channels operational. */
component {

    property name="wirebox" inject="wirebox";
    public WebPushRuntime function init( required struct properties ) {
        variables.configuration = arguments.properties;
        return this;
    }


    public boolean function enabled() {
        return structKeyExists( variables.configuration, "enabled" ) && variables.configuration.enabled;
    }

    public string function context( required any user ) {
        if ( isCustomFunction( variables.configuration.context ?: "" ) ) {
            return variables.configuration.context( arguments.user );
        }
        return arguments.user.getNotifiableType() & "|" & arguments.user.getNotifiableId() & "|" & variables.configuration.origin;
    }

    public any function cipher() {
        return new megaphone.models.SubscriptionCipher(
            variables.configuration.activeStorageKeyId,
            isStruct( variables.configuration.storageKeys ) ? variables.configuration.storageKeys : deserializeJSON(
                variables.configuration.storageKeys
            )
        );
    }

    public struct function enrollmentConfiguration() {
        if ( !enabled() ) {
            return { "available": false };
        }
        try {
            var storage = cipher();
            var deliveryTransport = transport();
            var keyFactory = createObject( "java", "java.security.KeyFactory" ).getInstance( "EC" );
            var publicKey = keyFactory.generatePublic(
                createObject( "java", "java.security.spec.X509EncodedKeySpec" ).init(
                    binaryDecode( variables.configuration.publicKey, "base64" )
                )
            );
            var classes = createObject( "java", "java.lang.Class" );
            var emptyTypes = createObject( "java", "java.lang.reflect.Array" ).newInstance(
                classes.forName( "java.lang.Class" ),
                javacast( "int", 0 )
            );
            var point = classes
                .forName( "java.security.interfaces.ECPublicKey" )
                .getMethod( "getW", emptyTypes )
                .invoke( publicKey, javacast( "object[]", [] ) );
            var bytes = binaryDecode(
                "04" & right( repeatString( "0", 64 ) & point.getAffineX().toString( 16 ), 64 ) & right(
                    repeatString( "0", 64 ) & point.getAffineY().toString( 16 ),
                    64
                ),
                "hex"
            );
            var encoded = reReplace(
                replace(
                    replace(
                        binaryEncode( bytes, "base64" ),
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
            return {
                "available": true,
                "applicationServerKey": encoded,
                "origin": variables.configuration.origin ?: ""
            };
        } catch ( any ignored ) {
            return { "available": false };
        }
    }

    public any function transport() {
        try {
            var factory = variables.wirebox.getInstance(
                variables.configuration.classFactory ?: "WebPushClassFactory@megaphone"
            );
            var keyFactory = createObject( "java", "java.security.KeyFactory" ).getInstance( "EC" );
            var privateKey = keyFactory.generatePrivate(
                createObject( "java", "java.security.spec.PKCS8EncodedKeySpec" ).init(
                    binaryDecode( variables.configuration.privateKey, "base64" )
                )
            );
            var publicKey = keyFactory.generatePublic(
                createObject( "java", "java.security.spec.X509EncodedKeySpec" ).init(
                    binaryDecode( variables.configuration.publicKey, "base64" )
                )
            );
            var verifier = createObject( "java", "java.security.Signature" ).getInstance( "SHA256withECDSA" );
            var challenge = charsetDecode( "Megaphone VAPID configuration", "UTF-8" );
            verifier.initSign( privateKey );
            verifier.update( challenge );
            var signature = verifier.sign();
            verifier.initVerify( publicKey );
            verifier.update( challenge );
            if ( !verifier.verify( signature ) ) {
                throw( message = "Push keys do not match." );
            }
            var pair = factory
                .create( "com.zerodeplibs.webpush.VAPIDKeyPairs" )
                .of(
                    factory.create( "com.zerodeplibs.webpush.key.PrivateKeySources" ).ofECPrivateKey( privateKey ),
                    factory.create( "com.zerodeplibs.webpush.key.PublicKeySources" ).ofECPublicKey( publicKey )
                );
            return new megaphone.models.WebPushTransport(
                classFactory = factory,
                vapidKeyPair = pair,
                subject = variables.configuration.subject,
                allowedHosts = variables.configuration.allowedHosts,
                timeoutSeconds = variables.configuration.timeoutSeconds ?: 10,
                httpClient = variables.configuration.httpClient ?: javacast( "null", "" )
            );
        } catch ( any ignored ) {
            throw(
                type = "Megaphone.Push.ConfigurationUnavailable",
                message = "Push delivery configuration is unavailable."
            );
        }
    }

}
