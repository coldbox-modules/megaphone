/** Recipient-owned choices with application-defined scopes. Inherit is represented by no row. */
component accessors="true" {

    property name="properties" type="struct" setter="false";
    property name="uuidGenerator" inject="java:java.util.UUID";
    property name="resolver" inject="PreferenceResolver@megaphone";

    /**
     * Stores the preference persistence configuration.
     * @returns PreferenceStore
     */
    public PreferenceStore function init( struct properties = {} ) {
        variables.properties = arguments.properties;
        return this;
    }

    /**
     * Stores one owned scope/channel choice; inherit removes the override.
     */
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
        return choicesMany( [ arguments ] )[ 1 ];
    }

    /** Batch the same recipient/type/scope reads without sharing a cache between callers. */
    public array function choicesMany( required array requests ) {
        var identities = [];
        var positions = [];
        var result = [];
        for ( var inputRequest in arguments.requests ) {
            var identity = recipient( inputRequest.notifiable );
            validateKey( inputRequest.notificationType, 160 );
            for ( var scopeKey in inputRequest.scopeKeys ) {
                validateKey( scopeKey, 100 );
            }
            result.append( [] );
            if ( !inputRequest.scopeKeys.isEmpty() ) {
                identity[ "notificationType" ] = inputRequest.notificationType;
                identity[ "scopeKey" ] = inputRequest.scopeKeys;
                identities.append( identity );
                positions.append( result.len() );
            }
        }
        var records = new megaphone.models.Storage.BulkRecords().read( () => newPreferenceQuery(), identities );
        for ( var index = 1; index <= positions.len(); index++ ) {
            var lookup = {};
            for ( var row in records[ index ] ) {
                if ( !structKeyExists( lookup, row.scopeKey ) ) {
                    lookup[ row.scopeKey ] = {};
                }
                lookup[ row.scopeKey ][ row.channel ] = row.choice;
            }
            result[ positions[ index ] ] = arguments.requests[ positions[ index ] ].scopeKeys.map( ( key ) => {
                return { "key": key, "choices": duplicate( lookup[ key ] ?: {} ) };
            } );
        }
        return result;
    }

    /** Ordered configurations use the same defaults, scope precedence and validation as scalar resolution. */
    public array function configurationMany( required array requests ) {
        var choices = choicesMany( arguments.requests );
        var result = [];
        for ( var index = 1; index <= arguments.requests.len(); index++ ) {
            var scopes = choices[ index ];
            result.append( {
                "scopes": scopes,
                "effective": variables.resolver.resolve( arguments.requests[ index ].defaults, scopes )
            } );
        }
        return result;
    }

    /**
     * Returns explicit stored scopes and the effective channel decisions for ordered application scopes.
     * @returns struct
     */
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
                var qb = newPreferenceQuery().where( arguments.constraints );
                for (
                    var key in [
                        "recipientType",
                        "recipientId",
                        "scopeKey",
                        "notificationType",
                        "channel"
                    ]
                ) {
                    qb.where( key, row[ key ] );
                }
                if (
                    qb.clone()
                        .lockForUpdate()
                        .get()
                        .isEmpty()
                ) {
                    continue;
                }
                qb.delete();
                removed++;
            }
        }
        return removed;
    }

    /**
     * Deletes records belonging to the supplied Notifiable.
     */
    public void function deleteRecipient( required any notifiable ) {
        var identity = recipient( arguments.notifiable );
        newPreferenceQuery()
            .where( "recipientType", identity.recipientType )
            .where( "recipientId", identity.recipientId )
            .delete();
    }

    /**
     * Reads and validates the Notifiable type and ID used for storage ownership.
     * @returns struct
     */
    private struct function recipient( required any notifiable ) {
        var type = arguments.notifiable.getNotifiableType();
        var id = arguments.notifiable.getNotifiableId();
        validateKey( type, 80 );
        validateKey( id, 100 );
        return { "recipientType": type, "recipientId": id };
    }
    /**
     * Checks that a preference key is nonempty and within its column limit.
     */
    private void function validateKey( required string value, required numeric maxLength ) {
        if ( !len( trim( arguments.value ) ) || len( arguments.value ) > arguments.maxLength ) {
            throw(
                type = "Megaphone.Preferences.InvalidKey",
                message = "A nonempty preference key within the storage limit is required."
            );
        }
    }
    /**
     * Builds a query for the configured preference table.
     * @returns any
     */
    private any function newPreferenceQuery() {
        return newQueryBuilder().from( getTableName() ).mergeDefaultOptions( getQueryOptions() );
    }
    /**
     * Returns the configured table name, or this store's default.
     * @returns string
     */
    public string function getTableName() {
        return variables.properties.table ?: "megaphone_preferences";
    }
    /**
     * Returns query options with an explicitly configured datasource taking precedence.
     * @returns struct
     */
    public struct function getQueryOptions() {
        var options = duplicate( variables.properties.queryOptions ?: {} );
        if ( variables.properties.keyExists( "datasource" ) ) {
            options.datasource = variables.properties.datasource;
        }
        return options;
    }

    /**
     * Supplies a fresh QueryBuilder through WireBox.
     * @returns QueryBuilder
     */
    private QueryBuilder function newQueryBuilder() provider="QueryBuilder@qb" {
    }

}
