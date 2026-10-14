/** emailDigest collects scheduled content or delivers a one-item immediate batch. */
component extends="BaseProvider" {

    property name="digests" inject="EmailDigestService@megaphone";

    /**
     * Returns the Provider type used to validate channel configuration.
     * @returns string
     */
    public string function getProviderName() {
        return "EmailDigestProvider";
    }
    /**
     * Identifies this Provider as a durable collection channel.
     * @returns boolean
     */
    public boolean function supportsCollection() {
        return true;
    }
    /**
     * Captures and validates toEmailDigest content without writing or sending.
     * @returns struct
     */
    public struct function getCollectionIntent( required any notifiable, required BaseNotification notification ) {
        var item = arguments.notification.routeForType( "emailDigest", arguments.notifiable, getName() );
        if (
            !isStruct( item ) || !len( item.digestName ?: "" ) || !len( item.itemKey ?: "" ) ||
            !isStruct( item.data ?: "" ) || !isNumeric( item.occurredAt ?: "" )
        ) {
            throw(
                type = "Megaphone.Digests.InvalidItem",
                message = "toEmailDigest must return digestName, itemKey, data and UTC occurredAt milliseconds."
            );
        }
        variables.digests.getDefinition( item.digestName );
        return item;
    }
    /**
     * Collects this Notification for its Notifiable and returns the populated Notification.
     * @returns BaseNotification
     */
    public BaseNotification function notify( required any notifiable, required BaseNotification notification ) {
        var item = getCollectionIntent( arguments.notifiable, arguments.notification );
        var collected = variables.digests.collect(
            notifiable = arguments.notifiable,
            digestName = item.digestName,
            itemKey = item.itemKey,
            data = item.data,
            occurredAt = item.occurredAt
        );
        if ( len( collected.deliveryId ?: "" ) ) {
            newDeliveryService().dispatch( collected.deliveryId );
        }
        return arguments.notification;
    }
    /**
     * Admits a captured collection intent using the current matching Notifiable.
     * @returns struct
     */
    public struct function collectPlanned( required any event, required struct intent ) {
        var item = intent.routingData.emailDigest;
        var recipient = newNotificationRuntime().getNotifiable( intent.notifiableType, intent.notifiableId );
        if (
            isNull( recipient ) || recipient.getNotifiableType() != intent.notifiableType ||
            compare(
                isValid( "uuid", intent.notifiableId ) ? lCase( toString( recipient.getNotifiableId() ) ) : toString(
                    recipient.getNotifiableId()
                ),
                isValid( "uuid", intent.notifiableId ) ? lCase( intent.notifiableId ) : intent.notifiableId
            ) != 0
        ) {
            throw(
                type = "Megaphone.Digests.RecipientMissing",
                message = "Collection requires its current matching notifiable."
            );
        }
        return variables.digests.collect(
            notifiable = recipient,
            digestName = item.digestName,
            itemKey = item.itemKey,
            data = item.data,
            occurredAt = item.occurredAt,
            enabled = intent.enabled,
            eventId = event.getId()
        );
    }
    /**
     * Supplies the lazy notification runtime through WireBox.
     * @returns any
     */
    private any function newNotificationRuntime() provider="NotificationRuntime@megaphone" {
    }
    /**
     * Supplies the existing durable transport dispatcher for synchronous immediate notification.
     * @returns any
     */
    private any function newDeliveryService() provider="NotificationDeliveryService@megaphone" {
    }

}
