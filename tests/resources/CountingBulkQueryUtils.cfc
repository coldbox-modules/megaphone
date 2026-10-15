/** Counts inference while retaining qb's real normalization and execution. */
component extends="qb.models.Query.QueryUtils" accessors="true" {

    property name="inferenceCounter";
    public string function inferSqlType( any value ) {
        variables.inferenceCounter.count++;
        return super.inferSqlType( argumentCollection = arguments );
    }

}
