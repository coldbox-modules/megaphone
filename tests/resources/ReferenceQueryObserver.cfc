/** Observes actual grammar execution and forwards the existing interceptor contract unchanged. */
component accessors="true" {

    property name="delegate";
    property name="counter";
    public any function processState( required string state, required struct data ) {
        record( arguments.state, arguments.data );
        return variables.delegate.processState( arguments.state, arguments.data );
    }
    public any function announce( required string state, required struct data ) {
        record( arguments.state, arguments.data );
        return variables.delegate.announce( arguments.state, arguments.data );
    }
    private void function record( required string state, required struct data ) {
        if ( compareNoCase( arguments.state, "postQBExecute" ) == 0 && isAdmissionInsert( arguments.data.sql ) ) {
            variables.counter.results.append( {
                "returning": findNoCase( " RETURNING ", arguments.data.sql ) > 0,
                "rows": isQuery( arguments.data.query ?: "" ) ? arguments.data.query.recordCount : -1
            } );
        }
        if ( compareNoCase( arguments.state, "preQBExecute" ) != 0 ) {
            return;
        }
        variables.counter.executions++;
        var sql = arguments.data.sql;
        if ( isAdmissionInsert( sql ) ) {
            var columns = findNoCase( "megaphone_deliveries", sql ) ? 14 : 9;
            variables.counter.inserts.append( { "rows": arguments.data.bindings.len() / columns, "bindings": arguments.data.bindings.len() } );
        }
        if ( findNoCase( "megaphone_bulk_records", sql ) ) {
            variables.counter.count++;
            variables.counter.sql.append( sql );
        }
    }

    private boolean function isAdmissionInsert( required string sql ) {
        return reFindNoCase( "^\s*INSERT\b", arguments.sql ) > 0 || reFindNoCase(
            "^\s*WITH ""megaphone_inserted"" AS\s*\(\s*INSERT\b",
            arguments.sql
        ) > 0;
    }

}
