component accessors="true" {

    property name="delegate";
    property name="queries";
    public any function processState( required string state, required struct data ) {
        if ( arguments.state == "preQBExecute" ) {
            variables.queries.append( { "sql": arguments.data.sql, "bindings": arguments.data.bindings } );
        }
        return variables.delegate.processState( argumentCollection = arguments );
    }
    public any function announce( required string state, required struct data ) {
        if ( arguments.state == "preQBExecute" ) {
            variables.queries.append( { "sql": arguments.data.sql, "bindings": arguments.data.bindings } );
        }
        return variables.delegate.announce( argumentCollection = arguments );
    }

}
