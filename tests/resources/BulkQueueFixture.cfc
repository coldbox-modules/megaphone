component extends="tests.resources.DurableQueueFixture" accessors="true" {

    property name="batches";
    public BulkQueueFixture function init( boolean fail = false ) {
        super.init( arguments.fail );
        variables.batches = [];
        return this;
    }
    public void function enqueueMany( required array deliveries, string connection, string queue ) {
        var batch = { "ids": arguments.deliveries.map( ( item ) => item.getId() ) };
        for ( var key in [ "connection", "queue" ] ) {
            if ( !isNull( arguments[ key ] ) ) {
                batch[ key ] = arguments[ key ];
            }
        }
        variables.batches.append( batch );
        for ( var delivery in arguments.deliveries ) {
            enqueue( delivery );
        }
    }

}
