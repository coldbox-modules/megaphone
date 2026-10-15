component extends="tests.resources.BulkQueueFixture" accessors="true" {

    property name="references";
    property name="referenceOptions";
    public BulkReferenceQueueFixture function init( boolean fail = false ) {
        super.init( arguments.fail );
        variables.references = [];
        variables.referenceOptions = [];
        return this;
    }
    public void function enqueueReferencesMany( required array references, string connection, string queue ) {
        variables.references.append( duplicate( arguments.references ), true );
        var options = {};
        for ( var key in [ "connection", "queue" ] ) {
            if ( !isNull( arguments[ key ] ) ) {
                options[ key ] = arguments[ key ];
            }
        }
        variables.referenceOptions.append( options );
        if ( variables.fail ) {
            throw( type = "QueueFixtureUnavailable", message = "Reference queue insertion failed before commit." );
        }
    }

}
