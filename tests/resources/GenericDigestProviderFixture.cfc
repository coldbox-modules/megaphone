component extends="megaphone.models.Providers.BaseProvider" accessors="true" {

    property name="outcome" default="accepted";
    property name="sent";

    function init( string name = "summaryEmail", struct properties = {} ) {
        super.init( argumentCollection = arguments );
        variables.sent = [];
        return this;
    }

    function getProviderName() {
        return "SummaryProvider";
    }

    function supportsDurableDelivery() {
        return true;
    }

    function prepareDelivery( notifiable, notification, delivery ) {
        return new megaphone.models.Delivery.DeliveryPreparation( { "data": notification.routeForType( "summary", notifiable, getName() ) } );
    }

    function sendDelivery( prepared, delivery ) {
        variables.sent.append( { "id": delivery.getId(), "data": prepared.getData() } );
        if ( variables.outcome == "throw" ) {
            throw( message = "Unknown provider outcome" );
        }
        return new megaphone.models.Delivery.DeliveryResult( { "status": variables.outcome, "providerReference": "fake-receipt", "retryDate": dateAdd( "s", -1, now() ) } );
    }

}
