/** Optional capability; synchronous INotificationProvider remains unchanged. */
interface {

    /**
     * Prepares one durable delivery without sending it.
     * @returns DeliveryPreparation
     */
    public DeliveryPreparation function prepareDelivery(
        required any notifiable,
        required any notification,
        required any delivery
    );
    /**
     * Sends one prepared delivery and returns an explicit transport outcome.
     * @returns DeliveryResult
     */
    public DeliveryResult function sendDelivery( required any prepared, required any delivery );

}
