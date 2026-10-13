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
        return newDeliveryPreparation();
    }
    public any function sendDelivery( required any prepared, required any delivery ) {
        variables.sends++;
        if ( variables.properties.failSending ?: false ) {
            throw( message = "Fixture transport outcome unknown." );
        }
        return newDeliveryResult().configure( { "status": "accepted", "providerReference": "fixture-receipt" } );
    }

    /** Supplies a fresh DeliveryPreparation through WireBox. */
    private megaphone.models.DeliveryPreparation function newDeliveryPreparation()
        provider="DeliveryPreparation@megaphone"
    {
    }

    /** Supplies a fresh DeliveryResult through WireBox. */
    private megaphone.models.DeliveryResult function newDeliveryResult() provider="DeliveryResult@megaphone" {
    }

}
