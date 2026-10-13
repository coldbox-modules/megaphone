/** Resolve optional application infrastructure lazily, after module activation. */
component singleton {

    property name="settings" inject="coldbox:moduleSettings:megaphone";
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
