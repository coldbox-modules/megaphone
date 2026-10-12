/** Recipient-owned sparse overrides; the application defines and authorizes scope order. */
component singleton {

    property name="store" inject="PreferenceStore@megaphone";

    public array function getPreferences(
        required any notifiable,
        required string notificationType,
        required array scopeKeys
    ) {
        return variables.store.choices( argumentCollection = arguments );
    }

    public void function setPreference(
        required any notifiable,
        required string notificationType,
        required string scopeKey,
        required string channelName,
        required string choice
    ) {
        var values = structCopy( arguments );
        values.channel = values.channelName;
        structDelete( values, "channelName" );
        variables.store.saveChoice( argumentCollection = values );
    }

    public struct function resolvePreferences(
        required any notifiable,
        required string notificationType,
        required struct defaults,
        required array scopeKeys
    ) {
        return variables.store.configuration( argumentCollection = arguments );
    }

    public void function importPreference(
        required any notifiable,
        required string notificationType,
        required string scopeKey,
        required string channelName,
        required string choice
    ) {
        var values = structCopy( arguments );
        values.channel = values.channelName;
        structDelete( values, "channelName" );
        variables.store.importChoice( argumentCollection = values );
    }

    public numeric function prunePreferences( required any constraints, numeric limit = 100 ) {
        return variables.store.pruneChoices( argumentCollection = arguments );
    }
    public void function deleteNotifiable( required any notifiable ) {
        variables.store.deleteRecipient( arguments.notifiable );
    }

}
