/** Optional capability for Providers that collect content instead of starting transport. */
interface displayName="INotificationCollectionProvider" {

    /**
     * Identifies the Provider as a collection channel during planning.
     * @returns boolean
     */
    public boolean function supportsCollection();

    /**
     * Captures collection content without writing or sending it.
     * @returns struct
     */
    public struct function getCollectionIntent( required any notifiable, required BaseNotification notification );

    /**
     * Admits one captured intent into durable collection in the publication transaction.
     * @returns struct
     */
    public struct function collectPlanned( required any event, required struct intent );

}
