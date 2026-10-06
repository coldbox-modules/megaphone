/** Optional standards-based request preparation. The SDK class factory is supplied by the consumer. */
component {

    function init(
        required any classFactory,
        required any vapidKeyPair,
        required string subject,
        required array allowedHosts,
        numeric timeoutSeconds = 10,
        any httpClient
    ) {
        if (
            !reFindNoCase( "^(mailto:[^\s]+@[^\s]+|https://[^\s]+)$", arguments.subject ) || arguments.allowedHosts.isEmpty()
        ) {
            throw(
                type = "Megaphone.Push.InvalidConfiguration",
                message = "Push requires a contact subject and trusted endpoint hosts."
            );
        }
        if (
            arguments.timeoutSeconds < 1 || arguments.timeoutSeconds > 60 || arguments.timeoutSeconds != fix(
                arguments.timeoutSeconds
            )
        ) {
            throw(
                type = "Megaphone.Push.InvalidConfiguration",
                message = "Push timeout must be between 1 and 60 seconds."
            );
        }
        for ( var host in arguments.allowedHosts ) {
            if ( !isSimpleValue( host ) || !reFindNoCase( "^(\*\.)?[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$", host ) ) {
                throw(
                    type = "Megaphone.Push.InvalidConfiguration",
                    message = "Trusted push hosts must be DNS names or explicit subdomain patterns."
                );
            }
        }
        variables.classFactory = arguments.classFactory;
        variables.vapidKeyPair = arguments.vapidKeyPair;
        variables.subject = arguments.subject;
        variables.allowedHosts = duplicate( arguments.allowedHosts );
        variables.timeoutSeconds = arguments.timeoutSeconds;
        variables.responsePolicy = new megaphone.models.WebPushResponsePolicy();
        variables.javaHttp = new megaphone.models.JavaHttpBridge();
        variables.customClient = !isNull( arguments.httpClient );
        variables.httpClient = variables.javaHttp.newClient( duration() );
        if ( !isNull( arguments.httpClient ) ) {
            variables.httpClient = arguments.httpClient;
        }
        return this;
    }

    /** Run before the durable dispatcher's transport-start marker; no external I/O occurs here. */
    public any function prepare( required struct subscription, required struct payload, numeric ttlSeconds = 3600 ) {
        if (
            arguments.ttlSeconds < 0 || arguments.ttlSeconds > 604800 || arguments.ttlSeconds != fix(
                arguments.ttlSeconds
            )
        ) {
            throw(
                type = "Megaphone.Push.InvalidRequest",
                message = "Push TTL must be an integer between zero and seven days."
            );
        }
        try {
            validateEndpoint( arguments.subscription.endpoint );
            validateKey( arguments.subscription.keys.p256dh, 65 );
            validateKey( arguments.subscription.keys.auth, 16 );
            var message = charsetDecode( serializeJSON( arguments.payload ), "UTF-8" );
            if ( createObject( "java", "java.lang.reflect.Array" ).getLength( message ) > 3993 ) {
                throw( message = "Payload exceeds the single-record limit." );
            }
            var destination = variables.classFactory.create( "com.zerodeplibs.webpush.PushSubscription" ).init();
            var keys = variables.classFactory.create( "com.zerodeplibs.webpush.PushSubscription$Keys" ).init();
            keys.setP256dh( arguments.subscription.keys.p256dh );
            keys.setAuth( arguments.subscription.keys.auth );
            destination.setKeys( keys );
            destination.setEndpoint( arguments.subscription.endpoint );
            var unit = createObject( "java", "java.util.concurrent.TimeUnit" );
            var builder = variables.classFactory
                .create( "com.zerodeplibs.webpush.httpclient.StandardHttpClientRequestPreparer" )
                .getBuilder()
                .pushSubscription( destination )
                .vapidJWTSubject( variables.subject )
                .vapidJWTExpiresAfter( javacast( "int", 15 ), unit.MINUTES )
                .pushMessage( message )
                .ttl( javacast( "long", arguments.ttlSeconds ), unit.SECONDS )
                .urgencyNormal()
                .build( variables.vapidKeyPair )
                .toRequestBuilder();
            return variables.javaHttp.withTimeout( builder, duration() );
        } catch ( any error ) {
            throw(
                type = "Megaphone.Push.InvalidRequest",
                message = "Unable to prepare a valid encrypted push request."
            );
        }
    }

    /** Call only after claiming work, checking eligibility, and marking transport started. */
    public struct function sendPrepared( required any request ) {
        validateEndpoint( variables.javaHttp.requestValue( arguments.request, "uri" ).toString() );
        if (
            variables.javaHttp.requestValue( arguments.request, "method" ) != "POST" || !variables.javaHttp
                .requestValue( arguments.request, "timeout" )
                .isPresent()
        ) {
            throw(
                type = "Megaphone.Push.InvalidRequest",
                message = "Push transport requires a prepared POST with a timeout."
            );
        }
        try {
            var handler = createObject( "java", "java.net.http.HttpResponse$BodyHandlers" ).discarding();
            var response = variables.customClient ? variables.httpClient.send( arguments.request, handler ) : variables.javaHttp.send(
                variables.httpClient,
                arguments.request,
                handler
            );
            var status = variables.customClient ? response.statusCode() : variables.javaHttp.responseValue(
                response,
                "statusCode"
            );
            var headers = variables.customClient ? response.headers() : variables.javaHttp.responseValue(
                response,
                "headers"
            );
            return variables.responsePolicy.classify(
                statusCode = status,
                retryAfter = headers.firstValue( "Retry-After" ).orElse( "" )
            );
        } catch ( any error ) {
            // Once send begins, neither a timeout nor a connection error proves non-acceptance.
            return { "outcome": "ambiguous", "reason": "push-acceptance-unknown", "retireSubscription": false };
        }
    }

    public void function validateEndpoint( required string endpoint ) {
        try {
            var uri = createObject( "java", "java.net.URI" ).init( arguments.endpoint );
            var host = lCase( uri.getHost() ?: "" );
            var allowed = false;
            for ( var pattern in variables.allowedHosts ) {
                pattern = lCase( pattern );
                if (
                    host == pattern || (
                        left( pattern, 2 ) == "*." && len( host ) > len( pattern ) - 1 && right(
                            host,
                            len( pattern ) - 1
                        ) == mid( pattern, 2, len( pattern ) - 1 )
                    )
                ) {
                    allowed = true;
                }
            }
            if (
                uri.getScheme() != "https" || !allowed || ( uri.getPort() != -1 && uri.getPort() != 443 ) || !isNull(
                    uri.getUserInfo()
                ) || !isNull( uri.getFragment() )
            ) {
                throw( message = "Untrusted endpoint." );
            }
        } catch ( any error ) {
            throw(
                type = "Megaphone.Push.InvalidEndpoint",
                message = "Push endpoints must use HTTPS on an explicitly trusted service host."
            );
        }
    }

    private void function validateKey( required string value, required numeric bytes ) {
        if ( !reFind( "^[A-Za-z0-9_-]+={0,2}$", arguments.value ) ) {
            throw( message = "Invalid key encoding." );
        }
        var decoded = createObject( "java", "java.util.Base64" ).getUrlDecoder().decode( arguments.value );
        if (
            createObject( "java", "java.lang.reflect.Array" ).getLength( decoded ) != arguments.bytes || (
                arguments.bytes == 65 && decoded[ 1 ] != 4
            )
        ) {
            throw( message = "Invalid key size or format." );
        }
    }

    private any function duration() {
        return createObject( "java", "java.time.Duration" ).ofSeconds( javacast( "long", variables.timeoutSeconds ) );
    }

}
