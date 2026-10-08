/** Invoke exported JDK interfaces so older CFML reflection does not require opening internal modules. */
component {

    function newClient( required any timeout ) {
        var builder = createObject( "java", "java.net.http.HttpClient" ).newBuilder();
        invokePublic(
            "java.net.http.HttpClient$Builder",
            builder,
            "followRedirects",
            [ "java.net.http.HttpClient$Redirect" ],
            [ createObject( "java", "java.net.http.HttpClient$Redirect" ).NEVER ]
        );
        invokePublic(
            "java.net.http.HttpClient$Builder",
            builder,
            "connectTimeout",
            [ "java.time.Duration" ],
            [ arguments.timeout ]
        );
        return invokePublic(
            "java.net.http.HttpClient$Builder",
            builder,
            "build",
            [],
            []
        );
    }
    function withTimeout( required any builder, required any timeout ) {
        invokePublic(
            "java.net.http.HttpRequest$Builder",
            arguments.builder,
            "timeout",
            [ "java.time.Duration" ],
            [ arguments.timeout ]
        );
        return invokePublic(
            "java.net.http.HttpRequest$Builder",
            arguments.builder,
            "build",
            [],
            []
        );
    }
    function send( required any client, required any preparedRequest, required any handler ) {
        return invokePublic(
            "java.net.http.HttpClient",
            arguments.client,
            "send",
            [ "java.net.http.HttpRequest", "java.net.http.HttpResponse$BodyHandler" ],
            [ arguments.preparedRequest, arguments.handler ]
        );
    }
    function requestValue( required any preparedRequest, required string method ) {
        return invokePublic(
            "java.net.http.HttpRequest",
            arguments.preparedRequest,
            arguments.method,
            [],
            []
        );
    }
    function responseValue( required any response, required string method ) {
        return invokePublic(
            "java.net.http.HttpResponse",
            arguments.response,
            arguments.method,
            [],
            []
        );
    }
    function bodyLength( required any preparedRequest ) {
        var publisher = requestValue( arguments.preparedRequest, "bodyPublisher" ).get();
        return invokePublic(
            "java.net.http.HttpRequest$BodyPublisher",
            publisher,
            "contentLength",
            [],
            []
        );
    }
    private any function invokePublic(
        required string interfaceName,
        required any target,
        required string method,
        required array types,
        required array values
    ) {
        var classes = createObject( "java", "java.lang.Class" );
        var arrays = createObject( "java", "java.lang.reflect.Array" );
        var parameterTypes = arrays.newInstance(
            classes.forName( "java.lang.Class" ),
            javacast( "int", arguments.types.len() )
        );
        for ( var index = 1; index <= arguments.types.len(); index++ ) {
            arrays.set( parameterTypes, javacast( "int", index - 1 ), classes.forName( arguments.types[ index ] ) );
        }
        var parameterValues = arrays.newInstance(
            classes.forName( "java.lang.Object" ),
            javacast( "int", arguments.values.len() )
        );
        for ( var index = 1; index <= arguments.values.len(); index++ ) {
            arrays.set( parameterValues, javacast( "int", index - 1 ), arguments.values[ index ] );
        }
        return classes
            .forName( arguments.interfaceName )
            .getMethod( arguments.method, parameterTypes )
            .invoke( arguments.target, parameterValues );
    }

}
