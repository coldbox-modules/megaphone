/** A named collection channel. The configured provider, not the channel name, selects toDigest(). */
component extends="EmailDigestProvider" {

    public string function getProviderName() {
        return "DigestProvider";
    }

    public struct function getCollectionIntent( required any notifiable, required BaseNotification notification ) {
        var properties = getProperties();
        var digestName = properties.digestName ?: "";
        if ( !len( digestName ) ) {
            throw(
                type = "Megaphone.Digests.InvalidDefinition",
                message = "A DigestProvider channel requires properties.digestName."
            );
        }
        var definition = variables.digests.getDefinition( digestName );
        if ( !len( definition.notification ?: "" ) ) {
            throw(
                type = "Megaphone.Digests.InvalidDefinition",
                message = "A generic collection channel requires a notification-based digest definition."
            );
        }
        var item = arguments.notification.routeForType( "digest", arguments.notifiable, getName() );
        if (
            !isStruct( item ) || !len( item.itemKey ?: "" ) || !isStruct( item.data ?: "" ) || !isNumeric(
                item.occurredAt ?: ""
            )
        ) {
            throw(
                type = "Megaphone.Digests.InvalidItem",
                message = "toDigest must return itemKey, data and UTC occurredAt milliseconds."
            );
        }
        if ( structKeyExists( item, "digestName" ) && compareNoCase( item.digestName, definition.name ) != 0 ) {
            throw(
                type = "Megaphone.Digests.InvalidItem",
                message = "toDigest cannot override the collection channel's digestName."
            );
        }
        var captured = duplicate( item );
        captured.digestName = definition.name;
        return captured;
    }

}
