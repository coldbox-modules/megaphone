component accessors="true" {

    property name="fail";
    property name="deliveries";
    function init( boolean fail = false ) {
        variables.fail = arguments.fail;
        variables.deliveries = [];
        return this;
    }
    function enqueue( required struct delivery ) {
        variables.deliveries.append( duplicate( arguments.delivery ) );
        if ( variables.fail ) {
            throw( type = "QueueFixtureUnavailable", message = "Queue adapter failed before commit." );
        }
    }

}
