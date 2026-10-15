component extends="megaphone.models.Delivery.NotificationSnapshotHasher" {

    function init( required struct counter ) {
        variables.counter = arguments.counter;
        variables.identity = createUUID();
        return this;
    }
    public any function snapshot( required any value ) {
        variables.counter.instances.append( variables.identity );
        return super.snapshot( arguments.value );
    }

}
