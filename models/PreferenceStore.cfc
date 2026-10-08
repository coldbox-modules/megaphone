/** Recipient-owned choices with application-defined scopes. Inherit is represented by no row. */
component accessors="true" {

    property name="properties";
    property name="resolver" inject="PreferenceResolver@megaphone";

    function init( struct properties = {} ) {
        variables.properties = arguments.properties;
        return this;
    }

    public void function saveChoice(
        required any notifiable,
        required string notificationType,
        required string scopeKey,
        required string channel,
        required string choice
    ) {
        var identity = recipient( arguments.notifiable );
        validateKey( arguments.notificationType, 160 );
        validateKey( arguments.scopeKey, 100 );
        validateKey( arguments.channel, 60 );
        local.choice = lCase( trim( arguments.choice ) );
        if ( !listFind( "inherit,on,off", choice ) ) {
            throw( type = "Megaphone.Preferences.InvalidChoice", message = "Choices must be inherit, on, or off." );
        }
        identity.append( { "scopeKey": arguments.scopeKey, "notificationType": arguments.notificationType, "channel": arguments.channel } );
        if ( choice == "inherit" ) {
            newPreferenceQuery()
                .where( "recipientType", identity.recipientType )
                .where( "recipientId", identity.recipientId )
                .where( "notificationType", identity.notificationType )
                .where( "scopeKey", identity.scopeKey )
                .where( "channel", identity.channel )
                .delete();
            return;
        }
        var values = duplicate( identity );
        values.append( { "choice": choice, "updatedDate": now() } );
        newPreferenceQuery().upsert(
            values = values,
            target = [
                "recipientType",
                "recipientId",
                "scopeKey",
                "notificationType",
                "channel"
            ],
            update = [ "choice", "updatedDate" ]
        );
    }

    /** Migration/backfill insertion that never replaces an existing explicit choice. */
    public void function importChoice(
        required any notifiable,
        required string notificationType,
        required string scopeKey,
        required string channel,
        required string choice
    ) {
        var identity = recipient( arguments.notifiable );
        validateKey( arguments.notificationType, 160 );
        validateKey( arguments.scopeKey, 100 );
        validateKey( arguments.channel, 60 );
        local.choice = lCase( trim( arguments.choice ) );
        if ( !listFind( "inherit,on,off", choice ) ) {
            throw( type = "Megaphone.Preferences.InvalidChoice", message = "Choices must be inherit, on, or off." );
        }
        if ( choice == "inherit" ) {
            return;
        }
        identity.append( {
            "scopeKey": arguments.scopeKey,
            "notificationType": arguments.notificationType,
            "channel": arguments.channel,
            "choice": choice,
            "updatedDate": now()
        } );
        newPreferenceQuery().insertIgnore( identity );
    }

    /** Ordered scopes supplied by the application; ownership is enforced before filtering. */
    public array function choices( required any notifiable, required string notificationType, required array scopeKeys ) {
        var identity = recipient( arguments.notifiable );
        validateKey( arguments.notificationType, 160 );
        if ( arguments.scopeKeys.isEmpty() ) {
            return [];
        }
        for ( var scopeKey in arguments.scopeKeys ) {
            validateKey( scopeKey, 100 );
        }
        var rows = newPreferenceQuery()
            .where( "recipientType", identity.recipientType )
            .where( "recipientId", identity.recipientId )
            .where( "notificationType", arguments.notificationType )
            .whereIn( "scopeKey", arguments.scopeKeys )
            .get();
        var lookup = {};
        for ( var row in rows ) {
            if ( !structKeyExists( lookup, row.scopeKey ) ) {
                lookup[ row.scopeKey ] = {};
            }
            lookup[ row.scopeKey ][ row.channel ] = row.choice;
        }
        return arguments.scopeKeys.map( ( key ) => {
            return { "key": key, "choices": duplicate( lookup[ key ] ?: {} ) };
        } );
    }

    public struct function configuration(
        required any notifiable,
        required string notificationType,
        required struct defaults,
        required array scopeKeys
    ) {
        var scopes = choices( arguments.notifiable, arguments.notificationType, arguments.scopeKeys );
        return { "scopes": scopes, "effective": variables.resolver.resolve( arguments.defaults, scopes ) };
    }

    /** Trusted maintenance supplies stale-scope constraints; candidates are rechecked under lock. */
    public numeric function pruneChoices( required any constraints, numeric limit = 100 ) {
        if ( arguments.limit < 1 || arguments.limit > 1000 || fix( arguments.limit ) != arguments.limit ) {
            throw(
                type = "Megaphone.Preferences.InvalidBatch",
                message = "Preference cleanup requires a batch between 1 and 1000."
            );
        }
        var rows = newPreferenceQuery()
            .where( arguments.constraints )
            .orderBy( "recipientType" )
            .orderBy( "recipientId" )
            .orderBy( "scopeKey" )
            .orderBy( "notificationType" )
            .orderBy( "channel" )
            .limit( arguments.limit )
            .get();
        var removed = 0;
        for ( var row in rows ) {
            transaction {
                var query = newPreferenceQuery().where( arguments.constraints );
                for (
                    var key in [
                        "recipientType",
                        "recipientId",
                        "scopeKey",
                        "notificationType",
                        "channel"
                    ]
                ) {
                    query.where( key, row[ key ] );
                }
                if (
                    query
                        .clone()
                        .lockForUpdate()
                        .get()
                        .isEmpty()
                ) {
                    continue;
                }
                query.delete();
                removed++;
            }
        }
        return removed;
    }

    public void function deleteRecipient( required any notifiable ) {
        var identity = recipient( arguments.notifiable );
        newPreferenceQuery()
            .where( "recipientType", identity.recipientType )
            .where( "recipientId", identity.recipientId )
            .delete();
    }

    private struct function recipient( required any notifiable ) {
        var type = arguments.notifiable.getNotifiableType();
        var id = arguments.notifiable.getNotifiableId();
        validateKey( type, 80 );
        validateKey( id, 100 );
        return { "recipientType": type, "recipientId": id };
    }
    private void function validateKey( required string value, required numeric maxLength ) {
        if ( !len( trim( arguments.value ) ) || len( arguments.value ) > arguments.maxLength ) {
            throw(
                type = "Megaphone.Preferences.InvalidKey",
                message = "A nonempty preference key within the storage limit is required."
            );
        }
    }
    private any function newPreferenceQuery() {
        return newQueryBuilder()
            .from( variables.properties.table ?: "megaphone_preferences" )
            .mergeDefaultOptions( variables.properties.queryOptions ?: {} );
    }
    private any function newQueryBuilder() provider="QueryBuilder@qb" {
    }

}
