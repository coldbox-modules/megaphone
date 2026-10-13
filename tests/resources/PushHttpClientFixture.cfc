/** Provider boundary fixture; accepts a real encrypted Java HttpRequest without making a network call. */
component {

    function init( numeric code = 201, string retryAfter = "", boolean fail = false ) {
        variables.code = arguments.code;
        variables.retryAfter = arguments.retryAfter;
        variables.fail = arguments.fail;
        variables.calls = 0;
        return this;
    }
    function send( required any preparedRequest, required any bodyHandler ) {
        variables.calls++;
        if ( variables.fail ) {
            throw( message = "fixture-secret transport outcome is unknown" );
        }
        return this;
    }
    function statusCode() {
        return variables.code;
    }
    function headers() {
        return this;
    }
    function firstValue( required string name ) {
        return createObject( "java", "java.util.Optional" ).of( variables.retryAfter );
    }
    function getCalls() {
        return variables.calls;
    }

}
