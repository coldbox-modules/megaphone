/** Deterministic JSON snapshots. Object keys are sorted; array order is significant. */
component singleton {

    public string function digest( required any value, struct context = {} ) {
        return lCase( hash( canonical( arguments.value ), "SHA-256" ) );
    }

    public any function snapshot( required any value ) {
        return deserializeJSON( canonical( arguments.value ) );
    }

    private string function canonical( required any value ) {
        if ( isNull( arguments.value ) ) {
            return "null";
        }
        if ( isObject( arguments.value ) ) {
            if ( isInstanceOf( arguments.value, "java.util.Date" ) ) {
                return serializeJSON( dateTimeFormat( arguments.value, "yyyy-mm-dd'T'HH:nn:ss.l'Z'", "UTC" ) );
            }
            throw(
                type = "Megaphone.Notification.InvalidSnapshot",
                message = "Queued properties must contain JSON data, not objects or callbacks."
            );
        }
        if ( isCustomFunction( arguments.value ) ) {
            throw(
                type = "Megaphone.Notification.InvalidSnapshot",
                message = "Queued properties cannot contain callbacks."
            );
        }
        if ( isArray( arguments.value ) ) {
            return "[" & arguments.value.map( ( value ) => canonical( value ) ).toList( "," ) & "]";
        }
        if ( isStruct( arguments.value ) ) {
            var keys = structKeyArray( arguments.value );
            keys.sort( "text" );
            var pairs = [];
            for ( var key in keys ) {
                pairs.append(
                    serializeJSON( key ) & ":" & (
                        isNull( arguments.value[ key ] ) ? "null" : canonical( arguments.value[ key ] )
                    )
                );
            }
            return "{" & pairs.toList( "," ) & "}";
        }
        if ( !isSimpleValue( arguments.value ) ) {
            throw(
                type = "Megaphone.Notification.InvalidSnapshot",
                message = "Queued properties must contain JSON data."
            );
        }
        return serializeJSON( arguments.value );
    }

}
