component singleton accessors="true" {

    property name="status" default="ready";
    public any function check( required any delivery, required any notifiable, required any event ) {
        return newDeliveryPreparation().configure( { "status": variables.status, "reason": "fixture-policy" } );
    }

    /** Supplies a fresh DeliveryPreparation through WireBox. */
    private megaphone.models.DeliveryPreparation function newDeliveryPreparation()
        provider="DeliveryPreparation@megaphone"
    {
    }

}
