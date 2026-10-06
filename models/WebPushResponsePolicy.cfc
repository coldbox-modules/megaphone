/** Classifies a completed push response without retaining provider bodies or subscription URLs. */
component {

    public struct function classify( required numeric statusCode, string retryAfter = "", date clock = now() ) {
        if (
            arguments.statusCode != fix( arguments.statusCode ) || arguments.statusCode < 100 || arguments.statusCode > 599
        ) {
            throw( type = "Megaphone.Push.InvalidResponse", message = "A valid HTTP response status is required." );
        }
        var result = { "outcome": "permanent", "reason": "push-rejected", "retireSubscription": false };
        if ( listFind( "201,202", arguments.statusCode ) ) {
            result.outcome = "accepted";
            result.reason = "push-service-accepted";
        } else if ( listFind( "404,410", arguments.statusCode ) ) {
            result.reason = "push-subscription-expired";
            result.retireSubscription = true;
        } else if ( arguments.statusCode == 408 ) {
            // A server timeout does not prove that the message was rejected before acceptance.
            result.outcome = "ambiguous";
            result.reason = "push-acceptance-unknown";
        } else if ( arguments.statusCode == 429 || arguments.statusCode >= 500 ) {
            result.outcome = "retryable";
            result.reason = arguments.statusCode == 429 ? "push-rate-limited" : "push-service-unavailable";
            result.retryDate = retryDate( arguments.retryAfter, arguments.clock );
        } else if ( arguments.statusCode < 400 ) {
            // Do not follow redirects or infer acceptance from an unexpected success response.
            result.outcome = "ambiguous";
            result.reason = "push-unexpected-response";
        } else if ( listFind( "401,403", arguments.statusCode ) ) {
            result.reason = "push-authentication-rejected";
        } else if ( arguments.statusCode == 413 ) {
            result.reason = "push-payload-too-large";
        }
        return result;
    }

    private date function retryDate( required string value, required date clock ) {
        var seconds = 60;
        var header = trim( arguments.value );
        if ( reFind( "^[0-9]{1,10}$", header ) ) {
            seconds = min( 86400, max( 1, val( header ) ) );
        } else if ( len( header ) && len( header ) <= 100 ) {
            try {
                var formatter = createObject( "java", "java.time.format.DateTimeFormatter" ).RFC_1123_DATE_TIME;
                var instant = createObject( "java", "java.time.ZonedDateTime" ).parse( header, formatter ).toInstant();
                var clockInstant = createObject( "java", "java.time.Instant" ).ofEpochMilli(
                    javacast( "long", arguments.clock.getTime() )
                );
                seconds = min( 86400, max( 1, instant.getEpochSecond() - clockInstant.getEpochSecond() ) );
            } catch ( any error ) {
                // Invalid provider hints fall back to the bounded default, without exposing header content.
                seconds = 60;
            }
        }
        return dateAdd( "s", seconds, arguments.clock );
    }

}
