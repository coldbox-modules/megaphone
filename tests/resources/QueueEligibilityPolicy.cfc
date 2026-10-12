component singleton accessors="true" {

    property name="status" default="ready";
    public any function check( required any delivery, required any notifiable, required any event ) {
        return new megaphone.models.DeliveryPreparation( { "status": variables.status, "reason": "fixture-policy" } );
    }

}
