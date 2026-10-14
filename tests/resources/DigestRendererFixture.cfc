component accessors="true" {

    property name="rendered";
    property name="onRender";
    function init() {
        variables.rendered = [];
        return this;
    }
    function render( notifiable, definition, batch, items ) {
        variables.rendered.append( { "batchId": batch.id, "digestName": definition.name, "keys": items.map( ( item ) => item.itemKey ) } );
        if ( !isNull( variables.onRender ) ) {
            variables.onRender();
        }
        return new tests.resources.DigestNotificationFixture().populate( { "keys": items.map( ( item ) => item.itemKey ) } );
    }

}
