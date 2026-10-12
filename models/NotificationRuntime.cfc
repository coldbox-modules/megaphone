/** Resolve optional application infrastructure lazily, after module activation. */
component singleton {

    property name="settings" inject="coldbox:moduleSettings:megaphone";
    property name="wirebox" inject="wirebox";

    public struct function getSettings() {
        return variables.settings;
    }

    public any function resolve( required string key, any fallback ) {
        var configured = variables.settings.durable[ arguments.key ] ?: "";
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

    public string function digest( required struct value, required struct context ) {
        var hasher = resolve(
            "snapshotHasher",
            variables.wirebox.getInstance( "NotificationSnapshotHasher@megaphone" )
        );
        return hasher.digest( arguments.value, arguments.context );
    }

    public any function getNotifiable( required string type, required string id ) {
        var resolver = resolve( "notifiableResolver" );
        if ( isNull( resolver ) ) {
            throw(
                type = "Megaphone.Configuration.MissingNotifiableResolver",
                message = "Configure durable.notifiableResolver to load a notifiable by type and ID."
            );
        }
        return resolver.resolve( arguments.type, arguments.id );
    }

}
