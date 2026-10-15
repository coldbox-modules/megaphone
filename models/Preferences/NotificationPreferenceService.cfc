/** Recipient-owned sparse overrides; the application defines and authorizes scope order. */
component singleton {

    property name="store" inject="PreferenceStore@megaphone";

    /**
     * Returns stored scope overrides for this Notifiable and notification type.
     * @returns array
     */
    public array function getPreferences(
        required any notifiable,
        required string notificationType,
        required array scopeKeys
    ) {
        return variables.store.choices( argumentCollection = arguments );
    }

    /**
     * Stores an on/off choice, or removes this exact scope/channel override for inherit.
     */
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

    /**
     * Applies channel defaults and ordered scope overrides, returning effective choices and their sources.
     * @returns struct
     */
    public struct function resolvePreferences(
        required any notifiable,
        required string notificationType,
        required struct defaults,
        required array scopeKeys
    ) {
        return variables.store.configuration( argumentCollection = arguments );
    }

    /** Resolves an ordered batch of the same arguments accepted by resolvePreferences. */
    public array function resolvePreferencesMany( required array requests ) {
        return variables.store.configurationMany( arguments.requests );
    }

    /**
     * Imports a preference without replacing a choice already stored.
     */
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

    /**
     * Deletes a bounded batch selected by trusted maintenance constraints.
     * @returns numeric
     */
    public numeric function prunePreferences( required any constraints, numeric limit = 100 ) {
        return variables.store.pruneChoices( argumentCollection = arguments );
    }
    /**
     * Removes this Notifiable's owned records during account cleanup.
     */
    public void function deleteNotifiable( required any notifiable ) {
        variables.store.deleteRecipient( arguments.notifiable );
    }

}
