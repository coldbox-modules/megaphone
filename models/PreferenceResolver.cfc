/** Ordered application scopes, from the broadest to the most specific. */
component singleton {

    public struct function resolve( required struct defaults, array scopes = [] ) {
        var resolved = {};
        for ( var channel in arguments.defaults ) {
            if ( !isBoolean( arguments.defaults[ channel ] ) ) {
                throw( type = "Megaphone.Preferences.InvalidDefault", message = "Channel defaults must be boolean." );
            }
            resolved[ channel ] = {
                "enabled": javacast( "boolean", arguments.defaults[ channel ] ),
                "source": "default"
            };
        }
        for ( var scope in arguments.scopes ) {
            if (
                !isStruct( scope ) || !structKeyExists( scope, "key" ) || !structKeyExists( scope, "choices" ) || !isStruct(
                    scope.choices
                )
            ) {
                throw(
                    type = "Megaphone.Preferences.InvalidScope",
                    message = "Each scope needs a key and channel choices."
                );
            }
            for ( var channel in scope.choices ) {
                if ( !structKeyExists( resolved, channel ) ) {
                    throw(
                        type = "Megaphone.Preferences.UnknownChannel",
                        message = "A preference refers to an unknown channel."
                    );
                }
                var choice = lCase( trim( scope.choices[ channel ] ) );
                if ( !listFind( "inherit,on,off", choice ) ) {
                    throw(
                        type = "Megaphone.Preferences.InvalidChoice",
                        message = "Choices must be inherit, on, or off."
                    );
                }
                if ( choice != "inherit" ) {
                    resolved[ channel ] = { "enabled": choice == "on", "source": scope.key };
                }
            }
        }
        return resolved;
    }

    /** New device registrations are included without copying preference rows. */
    public array function selectDevices( required array devices, array excludedIds = [] ) {
        var selected = [];
        var seen = {};
        for ( var device in arguments.devices ) {
            if ( !isStruct( device ) || !structKeyExists( device, "id" ) || !len( trim( device.id ) ) ) {
                throw(
                    type = "Megaphone.Preferences.InvalidDevice",
                    message = "A device needs a stable registration ID."
                );
            }
            if ( structKeyExists( device, "active" ) && !device.active ) {
                continue;
            }
            if ( !arguments.excludedIds.findNoCase( device.id ) && !structKeyExists( seen, device.id ) ) {
                seen[ device.id ] = true;
                selected.append( duplicate( device ) );
            }
        }
        return selected;
    }

}
