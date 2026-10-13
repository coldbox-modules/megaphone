component extends="megaphone.models.Providers.BaseProvider" {

    property name="sendCount" default="0";
    property name="outcome" default="accepted";

    public string function getProviderName() {
        return "QueueOutcomeProvider";
    }
    public megaphone.models.BaseNotification function notify(
        required any notifiable,
        required megaphone.models.BaseNotification notification
    ) {
        return arguments.notification;
    }
    public megaphone.models.Delivery.DeliveryPreparation function prepareDelivery(
        required any notifiable,
        required any notification,
        required any delivery
    ) {
        return newDeliveryPreparation();
    }
    public megaphone.models.Delivery.DeliveryResult function sendDelivery(
        required any prepared,
        required any delivery
    ) {
        variables.sendCount++;
        if ( variables.outcome == "throw" ) {
            throw( type = "QueueTransportUnknown", message = "Unknown acceptance" );
        }
        return newDeliveryResult().configure( { "status": variables.outcome } );
    }
    public numeric function getSendCount() {
        return variables.sendCount;
    }
    public void function setOutcome( required string outcome ) {
        variables.outcome = arguments.outcome;
    }

    /** Supplies a fresh DeliveryPreparation through WireBox. */
    private megaphone.models.Delivery.DeliveryPreparation function newDeliveryPreparation()
        provider="DeliveryPreparation@megaphone"
    {
    }

    /** Supplies a fresh DeliveryResult through WireBox. */
    private megaphone.models.Delivery.DeliveryResult function newDeliveryResult() provider="DeliveryResult@megaphone" {
    }

}
