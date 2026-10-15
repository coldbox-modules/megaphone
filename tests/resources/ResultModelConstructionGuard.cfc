/** A no-result admission must never enter a result-model construction path. */
component {

    public any function init() {
        throw( type = "UnexpectedResultModel", message = "No-result admission constructed a public result model." );
    }

}
