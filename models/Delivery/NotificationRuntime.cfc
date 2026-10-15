/** Resolve optional application infrastructure lazily, after module activation. */
component singleton {

    property name="settings" inject="box:moduleSettings:megaphone";
    property name="wirebox" inject="wirebox";

    /**
     * Returns the module settings used to resolve queue infrastructure.
     * @returns struct
     */
    public struct function getSettings() {
        return variables.settings;
    }

    /**
     * Resolves the configured WireBox mapping or instance, with an optional fallback.
     * @returns any
     */
    public any function resolve( required string key, any fallback ) {
        var configured = variables.settings.queue[ arguments.key ] ?: "";
        if ( isSimpleValue( configured ) && len( configured ) ) {
            return variables.wirebox.getInstance( configured );
        }
        if ( !isSimpleValue( configured ) ) {
            return configured;
        }
        if ( !isNull( arguments.fallback ) ) {
            return arguments.fallback;
        }
        return;
    }

    /**
     * Hashes a snapshot using the application hasher or the deterministic default.
     * @returns string
     */
    public string function digest( required struct value, required struct context ) {
        var hasher = resolve(
            "snapshotHasher",
            variables.wirebox.getInstance( "NotificationSnapshotHasher@megaphone" )
        );
        return hasher.digest( arguments.value, arguments.context );
    }

    /** Optional bulk hashing keeps custom canonicalization identical and ordered. */
    public array function digestMany( required array entries ) {
        var hasher = resolve(
            "snapshotHasher",
            variables.wirebox.getInstance( "NotificationSnapshotHasher@megaphone" )
        );
        var result = [];
        if ( isCustomFunction( hasher.digestMany ?: "" ) ) {
            result = hasher.digestMany( arguments.entries );
        } else {
            for ( var entry in arguments.entries ) {
                result.append( hasher.digest( entry.value, entry.context ) );
            }
        }
        if ( !isArray( result ) || result.len() != arguments.entries.len() ) {
            throw(
                type = "Megaphone.Notification.InvalidHashes",
                message = "A bulk hasher must return one hash per snapshot in input order."
            );
        }
        for ( var digest in result ) {
            if ( !isSimpleValue( digest ) || !len( trim( digest ) ) ) {
                throw(
                    type = "Megaphone.Notification.InvalidHashes",
                    message = "Snapshot hashes must be nonempty strings."
                );
            }
        }
        return result;
    }

    /**
     * Loads the current Notifiable through the application resolver.
     * @returns any
     */
    public any function getNotifiable( required string type, required string id ) {
        var resolver = resolve( "notifiableResolver" );
        if ( isNull( resolver ) ) {
            throw(
                type = "Megaphone.Configuration.MissingNotifiableResolver",
                message = "Configure queue.notifiableResolver to load a notifiable by type and ID."
            );
        }
        return resolver.resolve( arguments.type, arguments.id );
    }

}
