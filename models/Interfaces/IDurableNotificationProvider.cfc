/** Optional capability; synchronous INotificationProvider remains unchanged. */
interface {

    public DeliveryPreparation function prepareDelivery(
        required any notifiable,
        required any notification,
        required any delivery
    );
    public DeliveryResult function sendDelivery( required any prepared, required any delivery );

}
