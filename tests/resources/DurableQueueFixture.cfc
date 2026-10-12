component accessors="true" {

    property name="fail";
    property name="deliveries";
    function init( boolean fail = false ) {
        variables.fail = arguments.fail;
        variables.deliveries = [];
        return this;
    }
    function enqueue( required any delivery ) {
        variables.deliveries.append( arguments.delivery.getMemento() );
        if ( variables.fail ) {
            throw( type = "QueueFixtureUnavailable", message = "Queue adapter failed before commit." );
        }
    }

}
