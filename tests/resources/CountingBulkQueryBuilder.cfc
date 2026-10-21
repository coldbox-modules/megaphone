/** Counts real grammar compilation without changing SQL, bindings, or execution. */
component extends="qb.models.Query.QueryBuilder" accessors="true" {

    property name="compilationCounter";
    public string function toSQL( any showBindings = false ) {
        variables.compilationCounter.count++;
        return super.toSQL( argumentCollection = arguments );
    }

}
