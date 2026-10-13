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
    public megaphone.models.DeliveryPreparation function prepareDelivery(
        required any notifiable,
        required any notification,
        required any delivery
    ) {
        return new megaphone.models.DeliveryPreparation();
    }
    public megaphone.models.DeliveryResult function sendDelivery( required any prepared, required any delivery ) {
        variables.sendCount++;
        if ( variables.outcome == "throw" ) {
            throw( type = "QueueTransportUnknown", message = "Unknown acceptance" );
        }
        return new megaphone.models.DeliveryResult( { "status": variables.outcome } );
    }
    public numeric function getSendCount() {
        return variables.sendCount;
    }
    public void function setOutcome( required string outcome ) {
        variables.outcome = arguments.outcome;
    }

}
