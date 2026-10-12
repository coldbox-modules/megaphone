component extends="megaphone.models.Providers.BaseProvider" accessors="true" {

    property name="sends" default="0";
    public string function getProviderName() {
        return "DurableProviderFixture";
    }
    public any function prepareDelivery( required any notifiable, required any notification, required any delivery ) {
        if ( structKeyExists( variables.properties, "onPrepare" ) ) {
            variables.properties.onPrepare( arguments.delivery );
        }
        if ( variables.properties.failPreparation ?: false ) {
            throw( message = "Fixture preparation failed." );
        }
        return new megaphone.models.DeliveryPreparation();
    }
    public any function sendDelivery( required any prepared, required any delivery ) {
        variables.sends++;
        if ( variables.properties.failSending ?: false ) {
            throw( message = "Fixture transport outcome unknown." );
        }
        return new megaphone.models.DeliveryResult( { "status": "accepted", "providerReference": "fixture-receipt" } );
    }

}
