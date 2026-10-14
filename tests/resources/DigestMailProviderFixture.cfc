component accessors="true" {

    property name="outcome" default="accepted";
    property name="sent";
    function init() {
        variables.sent = [];
        return this;
    }
    function supportsDurableDelivery() {
        return true;
    }
    function prepareDelivery( notifiable, notification, delivery ) {
        return new megaphone.models.Delivery.DeliveryPreparation( { "data": notification.getQueueProperties() } );
    }
    function sendDelivery( prepared, delivery ) {
        variables.sent.append( { "id": delivery.getId(), "keys": prepared.getData().keys } );
        if ( variables.outcome == "throw" ) {
            throw( message = "Unknown provider outcome" );
        }
        return new megaphone.models.Delivery.DeliveryResult( { "status": variables.outcome, "providerReference": "test-receipt", "retryDate": dateAdd( "s", -1, now() ) } );
    }

}
