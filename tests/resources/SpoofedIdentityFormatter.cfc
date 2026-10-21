/** The private callback name alone does not prove stock QueryBuilder ownership. */
component {

    request.megaphoneSpoofedFormatterCalls = 0;
    public any function formatter() {
        return variables.identityColumnFormatter;
    }
    public numeric function getCalls() {
        return request.megaphoneSpoofedFormatterCalls;
    }
    private any function identityColumnFormatter( required any column ) {
        request.megaphoneSpoofedFormatterCalls++;
        return arguments.column == "sourcePayloadHash" ? "payloadHash" : arguments.column;
    }

}
